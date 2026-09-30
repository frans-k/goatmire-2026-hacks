# Load test for the relay: many simulated badges, reporting joins, snapshot gaps and refusals.
# Run from raycaster/ (it loads lib/relay_wire.ex and lib/engine.ex from there).
# Stress the relay with many simulated badges.
#   RELAY_TOKEN=... elixir stress.exs wss://host COUNT SECONDS [ramp_ms_between_joins]
# Every badge speaks through Raycaster.RelayWire, like the real firmware.
# Reports: join success/full/failed, connect+join latency, snapshot gap p50/p95/max,
# snapshots per badge per second, drops, catches.

Mix.install([{:websockex, "~> 0.4"}])

repo = "/Users/frans/code/goatmire2026/goatmire-2026-hacks/raycaster"
Code.require_file("lib/relay_wire.ex", repo)
Code.require_file("lib/engine.ex", repo)

[base, count, seconds | rest] = System.argv()
count = String.to_integer(count)
seconds = String.to_integer(seconds)
ramp = case rest do [r] -> String.to_integer(r); _ -> 20 end
token = System.get_env("RELAY_TOKEN")

defmodule Bot do
  use WebSockex
  @grid Raycaster.Engine.grid()

  def start(base, n, token, collector) do
    chip = "STRESS" <> String.pad_leading(Integer.to_string(n), 3, "0")
    {x, y} = Stream.repeatedly(fn -> {:rand.uniform(4095), :rand.uniform(4095)} end)
             |> Enum.find(fn {x, y} -> open?(x, y) end)
    url = Raycaster.RelayWire.url(base, chip, token)
    t0 = System.monotonic_time(:millisecond)
    WebSockex.start(url, __MODULE__,
      %{n: n, c: collector, x: x, y: y, angle: :rand.uniform(65_535), out: false, t0: t0, slot: nil},
      handle_initial_conn_failure: true)
  end

  defp open?(x, y), do: elem(@grid, div(y, 256) * 16 + div(x, 256)) == 0

  def handle_connect(_c, s) do
    send(self(), :join)
    send(s.c, {:connected, s.n, System.monotonic_time(:millisecond) - s.t0})
    {:ok, s}
  end

  def handle_info(:join, s), do: {:reply, {:text, Raycaster.RelayWire.join("1")}, s}
  def handle_info(:hb, s) do
    Process.send_after(self(), :hb, 25_000)
    {:reply, {:text, Raycaster.RelayWire.heartbeat()}, s}
  end
  def handle_info(:step, %{out: true} = s), do: (Process.send_after(self(), :step, 1000); {:ok, s})
  def handle_info(:step, s) do
    Process.send_after(self(), :step, 1000)
    r = s.angle * 2 * :math.pi() / 65_536
    nx = s.x + round(:math.cos(r) * 128)
    ny = s.y + round(:math.sin(r) * 128)
    s =
      if nx > 60 and ny > 60 and nx < 4030 and ny < 4030 and open?(nx + 60, ny + 60) and open?(nx - 60, ny - 60),
        do: %{s | x: nx, y: ny},
        else: %{s | angle: :rand.uniform(65_535)}
    {:reply, {:text, Raycaster.RelayWire.pos("1", "2", s.x, s.y)}, s}
  end
  def handle_info(:respawn, s),
    do: {:reply, {:text, Raycaster.RelayWire.respawn("1", "3")}, %{s | out: false, x: 384, y: 384}}

  def handle_frame({:text, text}, s) do
    case Raycaster.RelayWire.decode(text, s.slot) do
      {:joined, room, slot, _max} ->
        send(s.c, {:joined, s.n, room, slot, System.monotonic_time(:millisecond) - s.t0})
        Process.send_after(self(), :step, 300 + :rand.uniform(700))
        Process.send_after(self(), :hb, 25_000)
        {:ok, %{s | slot: slot}}
      {:players, p, _g} ->
        send(s.c, {:snap, s.n, System.monotonic_time(:millisecond), length(p), byte_size(text)})
        {:ok, s}
      :caught ->
        send(s.c, {:caught, s.n})
        Process.send_after(self(), :respawn, 2000)
        {:ok, %{s | out: true}}
      :ignore ->
        # a join error (full) arrives as an error phx_reply, which decode ignores
        if String.contains?(text, "\"error\""), do: send(s.c, {:refused, s.n, text})
        {:ok, s}
    end
  end

  def handle_disconnect(status, s) do
    send(s.c, {:down, s.n, inspect(status[:reason])})
    {:ok, s}
  end
end

me = self()

failed =
  for n <- 1..count, reduce: [] do
    acc ->
      Process.sleep(ramp)
      Task.start(fn ->
        case Bot.start(base, n, token, me) do
          {:ok, _pid} -> :ok
          {:error, e} -> send(me, {:down, n, "start: " <> inspect(e)})
        end
      end)
      acc
  end

deadline = System.monotonic_time(:millisecond) + seconds * 1000
IO.puts("started #{count} bots (#{length(failed)} could not connect); measuring #{seconds}s more")

init = %{conn: [], joined: [], refused: [], snaps: %{}, gaps: [], sizes: [], caught: 0, down: [], counts: []}

loop = fn loop, st ->
  left = deadline - System.monotonic_time(:millisecond)
  if left <= 0 do
    st
  else
    receive do
      {:connected, _n, ms} -> loop.(loop, %{st | conn: [ms | st.conn]})
      {:joined, n, room, slot, ms} -> loop.(loop, %{st | joined: [{n, room, slot, ms} | st.joined]})
      {:refused, n, t} -> loop.(loop, %{st | refused: [{n, t} | st.refused]})
      {:snap, n, t, k, bytes} ->
        gaps = case st.snaps do
          %{^n => last} -> [t - last | st.gaps]
          _ -> st.gaps
        end
        loop.(loop, %{st | snaps: Map.put(st.snaps, n, t), gaps: gaps, sizes: [{k, bytes} | st.sizes]})
      {:caught, _} -> loop.(loop, %{st | caught: st.caught + 1})
      {:down, n, r} -> loop.(loop, %{st | down: [{n, r} | st.down]})
    after
      min(left, 1000) -> loop.(loop, st)
    end
  end
end

st = loop.(loop, init)

pct = fn list, p ->
  s = Enum.sort(list)
  if s == [], do: nil, else: Enum.at(s, min(length(s) - 1, trunc(length(s) * p)))
end

IO.puts("--- results ---")
IO.puts("websocket connected: #{length(st.conn)}; connect ms p50/p95/max: #{pct.(st.conn, 0.5)}/#{pct.(st.conn, 0.95)}/#{Enum.max(st.conn, fn -> nil end)}")
jl = Enum.map(st.joined, &elem(&1, 3))
IO.puts("joined: #{length(st.joined)}; join-complete ms p50/p95/max: #{pct.(jl, 0.5)}/#{pct.(jl, 0.95)}/#{Enum.max(jl, fn -> nil end)}")
rooms = st.joined |> Enum.group_by(&elem(&1, 1)) |> Enum.map(fn {r, l} -> {r, length(l)} end) |> Enum.sort()
IO.puts("rooms: #{inspect(rooms)}")
IO.puts("refused (e.g. full): #{length(st.refused)} #{inspect(Enum.take(st.refused, 1))}")
IO.puts("snapshot gaps ms p50/p95/p99/max: #{pct.(st.gaps, 0.5)}/#{pct.(st.gaps, 0.95)}/#{pct.(st.gaps, 0.99)}/#{Enum.max(st.gaps, fn -> nil end)}  (n=#{length(st.gaps)}; ideal 1000)")
IO.puts("bots that heard snapshots: #{map_size(st.snaps)}")
bytes = Enum.map(st.sizes, &elem(&1, 1))
IO.puts("snapshot bytes p50/max: #{pct.(bytes, 0.5)}/#{Enum.max(bytes, fn -> nil end)}")
IO.puts("caught by goat: #{st.caught}")
IO.puts("unexpected disconnects: #{length(st.down)} #{inspect(Enum.take(st.down, 3))}")
IO.puts("connect failures: #{inspect(Enum.take(failed, 3))}")
System.halt(0)
