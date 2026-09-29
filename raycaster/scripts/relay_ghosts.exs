# Plays other badges against the relay server, so the game can be tried with one
# badge, and so the badge's frame code is checked against the real server: every
# ghost speaks and reads through Raycaster.RelayWire, the module the badge runs.
#
#     elixir scripts/relay_ghosts.exs ws://localhost:4040 [count] [seconds]
#
# Defaults to 3 ghosts for 120 seconds. They wander the map, one position a second.

Mix.install([{:websockex, "~> 0.4"}])

Code.require_file("../lib/relay_wire.ex", __DIR__)
Code.require_file("../lib/engine.ex", __DIR__)


{base, count, seconds} =
  case System.argv() do
    [base] ->
      {base, 3, 120}

    [base, count] ->
      {base, String.to_integer(count), 120}

    [base, count, seconds] ->
      {base, String.to_integer(count), String.to_integer(seconds)}

    _ ->
      IO.puts(:stderr, "usage: elixir scripts/relay_ghosts.exs ws://host:4040 [count] [seconds]") &&
        System.halt(1)
  end

defmodule Ghost do
  use WebSockex

  @grid Raycaster.Engine.grid()
  @step 128

  def start(base, n, report) do
    chip = "GHOST" <> String.pad_leading(Integer.to_string(n), 2, "0")

    state = %{
      n: n,
      report: report,
      slot: nil,
      room: nil,
      seen: 0,
      others: 0,
      angle: :rand.uniform(65_535)
    }

    {x, y} = start_at()

    WebSockex.start_link(
      Raycaster.RelayWire.url(base, chip),
      __MODULE__,
      Map.merge(state, %{x: x, y: y})
    )
  end

  defp open?(x, y),
    do:
      x >= 0 and y >= 0 and x < 4096 and y < 4096 and
        elem(@grid, div(y, 256) * 16 + div(x, 256)) == 0

  defp start_at do
    Stream.repeatedly(fn -> {:rand.uniform(4095), :rand.uniform(4095)} end)
    |> Enum.find(fn {x, y} -> open?(x, y) end)
  end

  @impl true
  def handle_connect(_conn, state) do
    send(self(), :join)
    {:ok, state}
  end

  @impl true
  def handle_info(:join, state), do: {:reply, {:text, Raycaster.RelayWire.join("1")}, state}

  def handle_info(:step, state) do
    Process.send_after(self(), :step, 1_000)
    radians = state.angle * 2 * :math.pi() / 65_536
    nx = state.x + round(:math.cos(radians) * @step)
    ny = state.y + round(:math.sin(radians) * @step)

    state =
      if open?(nx + 60, ny + 60) and open?(nx - 60, ny - 60),
        do: %{state | x: nx, y: ny},
        else: %{state | angle: :rand.uniform(65_535)}

    state =
      if :rand.uniform(4) == 1,
        do: %{state | angle: rem(state.angle + :rand.uniform(9_000) - 4_500 + 65_536, 65_536)},
        else: state

    {:reply, {:text, Raycaster.RelayWire.pos("1", "2", state.x, state.y)}, state}
  end

  @impl true
  def handle_frame({:text, text}, state) do
    case Raycaster.RelayWire.decode(text, state.slot) do
      {:joined, room, slot, max} ->
        send(state.report, {:joined, state.n, room, slot, max})
        Process.send_after(self(), :step, 300)
        {:ok, %{state | slot: slot, room: room}}

      {:players, players} ->
        send(state.report, {:players, state.n, length(players)})
        {:ok, %{state | seen: state.seen + 1, others: length(players)}}

      :ignore ->
        {:ok, state}
    end
  end

  @impl true
  def handle_disconnect(_status, state), do: {:ok, state}
end

ghosts = for n <- 1..count, do: elem(Ghost.start(base, n, self()), 1)

deadline = System.monotonic_time(:millisecond) + seconds * 1000

report = fn report, joined, latest ->
  left = deadline - System.monotonic_time(:millisecond)

  if left <= 0 do
    {joined, latest}
  else
    receive do
      {:joined, n, room, slot, max} ->
        IO.puts("ghost #{n}: room #{room}, slot #{slot} of #{max}")
        report.(report, Map.put(joined, n, {room, slot}), latest)

      {:players, n, others} ->
        report.(report, joined, Map.put(latest, n, others))
    after
      min(left, 1_000) -> report.(report, joined, latest)
    end
  end
end

{joined, latest} = report.(report, %{}, %{})

IO.puts(
  "joined: #{map_size(joined)} of #{count}; each ghost last saw #{inspect(Enum.sort(latest))} others"
)

Enum.each(ghosts, fn pid -> Process.exit(pid, :normal) end)
