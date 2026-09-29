# Plays other badges, so the game can be tried with just one: a few ghosts wander
# the map, publishing their positions the way a badge does.
#
#     elixir scripts/ghosts.exs [count] [seconds]
#
# Defaults to 3 ghosts for 120 seconds. They say goodbye when the time is up, or
# on Ctrl-C twice; the broker forgets them after four seconds anyway.
# Same broker as config/config.exs.

Mix.install([
  {:amqtt_client,
   github: "atomvm/amqtt", ref: "35fc07b37d1f76f25397c1d4355c91dd17149318", sparse: "amqtt_client"}
])

Code.require_file("../lib/wire.ex", __DIR__)
Code.require_file("../lib/engine.ex", __DIR__)

{count, seconds} =
  case System.argv() do
    [] -> {3, 120}
    [count] -> {String.to_integer(count), 120}
    [count, seconds] -> {String.to_integer(count), String.to_integer(seconds)}
  end

host = ~c"test.mosquitto.org"
grid = Raycaster.Engine.grid()

open? = fn x, y ->
  x >= 0 and y >= 0 and x < 4096 and y < 4096 and elem(grid, div(y, 256) * 16 + div(x, 256)) == 0
end

{:ok, client} =
  :amqtt_client.connect(%{
    host: host,
    port: 1883,
    client_id: "raycaster-ghosts-#{:rand.uniform(100_000)}"
  })

receive do
  {:mqtt, ^client, :connack, _} -> :ok
after
  10_000 ->
    IO.puts(:stderr, "no answer from #{host}")
    System.halt(1)
end

colours = [0xE0433A, 0x3AA0E0, 0x3AE07A, 0xE0C93A, 0xB03AE0, 0xE07A3A]

# Start each in open floor, facing a random way.
ghosts =
  for n <- 1..count do
    {x, y} =
      Stream.repeatedly(fn -> {:rand.uniform(4095), :rand.uniform(4095)} end)
      |> Enum.find(fn {x, y} -> open?.(x, y) end)

    %{
      id: "GHOST#{String.pad_leading(Integer.to_string(n), 2, "0")}",
      x: x,
      y: y,
      a: :rand.uniform(65_535),
      colour: Enum.at(colours, rem(n - 1, length(colours)))
    }
  end

IO.puts(
  "#{count} ghost(s) on #{host} for #{seconds}s, ids #{Enum.map_join(ghosts, ", ", & &1.id)}"
)

# A cell a second, at two updates a second: what a badge sends.
step = 128

tick = fn ghosts ->
  Enum.map(ghosts, fn g ->
    # Angle 0 is east and 16384 is a quarter turn; the engine's y grows downward.
    radians = g.a * 2 * :math.pi() / 65_536
    nx = g.x + round(:math.cos(radians) * step)
    ny = g.y + round(:math.sin(radians) * step)

    g =
      if open?.(nx + 60, ny + 60) and open?.(nx - 60, ny - 60) do
        %{g | x: nx, y: ny}
      else
        %{g | a: :rand.uniform(65_535)}
      end

    # Now and then a slight turn, so they do not walk in straight lines.
    if :rand.uniform(6) == 1,
      do: %{g | a: rem(g.a + :rand.uniform(9_000) - 4_500 + 65_536, 65_536)},
      else: g
  end)
end

publish = fn g ->
  :amqtt_client.publish(client, Raycaster.Wire.topic(g.id), Raycaster.Wire.encode(g, g.colour), 0)
end

finish = fn ghosts ->
  Enum.each(ghosts, fn g -> :amqtt_client.publish(client, Raycaster.Wire.topic(g.id), <<>>, 0) end)

  Process.sleep(300)
  :amqtt_client.disconnect(client)
end

loop = fn loop, ghosts, left ->
  if left <= 0 do
    finish.(ghosts)
  else
    Enum.each(ghosts, publish)
    Process.sleep(500)
    loop.(loop, tick.(ghosts), left - 500)
  end
end

loop.(loop, ghosts, seconds * 1000)
IO.puts("done")
