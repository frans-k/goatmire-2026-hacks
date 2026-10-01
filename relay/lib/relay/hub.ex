defmodule Relay.Hub do
  @moduledoc """
  Holds the rooms and tells every player in each of them, once a tick, where
  everyone stands.

  A badge sends where it is now and then and hears one message a tick, however
  many others there are. Taking in a message costs a badge about ten milliseconds,
  so one snapshot beats one message per player, and everything else here exists to
  keep it that way: the rooms do the sorting, this only sends.

  A player is a process, the websocket handler, and is out of its room when that
  process ends. It is sent `{:snap, frame}`, a Phoenix frame ready to push, and
  `{:caught, frame}` when the room's goat catches it.

  The goats move on a timer of their own, `goat_ms` (100), much more often than
  the snapshot goes out: the badges see the goat jump once a tick, but it walks,
  sees and catches in small steps in between.
  """

  use GenServer

  alias Relay.Rooms
  alias Relay.Stats

  @topic "raycaster:lobby"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The topic badges join."
  def topic, do: @topic

  @doc """
  Puts `pid` in a room. Returns `{room, slot, max}`, or `{:error, :full}` when the
  server already holds as many players as `:max_players` allows (300).

  `ghost: true` is for a player that is not a badge, see `Relay.Ghost`: it is in the room
  like any other, but the counts of who is playing leave it out.
  """
  def join(pid, opts \\ []),
    do: GenServer.call(__MODULE__, {:join, pid, Keyword.get(opts, :ghost, false)})

  @doc "How many of the players are ghosts."
  def ghost_count, do: GenServer.call(__MODULE__, :ghost_count)

  @doc "Where `pid` stands, as heard now."
  def move(pid, x, y), do: GenServer.cast(__MODULE__, {:move, pid, x, y, now()})

  def leave(pid), do: GenServer.cast(__MODULE__, {:leave, pid})

  @doc "Back in the game after being caught."
  def respawn(pid), do: GenServer.cast(__MODULE__, {:respawn, pid, now()})

  @doc "The rooms and how many are in each."
  def counts, do: GenServer.call(__MODULE__, :counts)

  @impl true
  def init(opts) do
    tick_ms = Keyword.get(opts, :tick_ms, Application.get_env(:relay, :tick_ms, 1_000))
    goat_ms = Keyword.get(opts, :goat_ms, Application.get_env(:relay, :goat_ms, 100))
    max = Keyword.get(opts, :max, 8)
    Process.send_after(self(), :tick, tick_ms)
    Process.send_after(self(), :goat, goat_ms)

    {:ok,
     %{
       rooms: Rooms.new(max),
       tick_ms: tick_ms,
       goat_ms: goat_ms,
       goat_at: now(),
       max: max,
       monitors: %{},
       ghosts: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:join, pid, ghost}, _from, state) do
    cap = Application.get_env(:relay, :max_players, 300)

    if Rooms.count(state.rooms) >= cap and not Rooms.member?(state.rooms, pid) do
      {:reply, {:error, :full}, state}
    else
      {rooms, {room, slot}} = Rooms.join(state.rooms, pid)
      monitors = Map.put_new_lazy(state.monitors, pid, fn -> Process.monitor(pid) end)
      ghosts = if ghost, do: MapSet.put(state.ghosts, pid), else: state.ghosts
      Stats.count(Rooms.count(rooms) - MapSet.size(ghosts))

      {:reply, {room, slot, state.max},
       %{state | rooms: rooms, monitors: monitors, ghosts: ghosts}}
    end
  end

  def handle_call(:counts, _from, state), do: {:reply, Rooms.counts(state.rooms), state}

  def handle_call(:ghost_count, _from, state), do: {:reply, MapSet.size(state.ghosts), state}

  @impl true
  def handle_cast({:move, pid, x, y, now}, state) do
    {:noreply, %{state | rooms: Rooms.move(state.rooms, pid, x, y, now)}}
  end

  def handle_cast({:leave, pid}, state), do: {:noreply, drop(state, pid)}

  def handle_cast({:respawn, pid, now}, state),
    do: {:noreply, %{state | rooms: Rooms.respawn(state.rooms, pid, now)}}

  @impl true
  def handle_info(:tick, state) do
    now = now()

    for room <- Rooms.rooms(state.rooms) do
      players = Rooms.snapshot(state.rooms, room, now)

      frame =
        JSON.encode!([
          nil,
          nil,
          @topic,
          "snap",
          %{"p" => players, "g" => Rooms.goat(state.rooms, room)}
        ])

      for {pid, _slot} <- Rooms.members(state.rooms, room), do: send(pid, {:snap, frame})
    end

    Process.send_after(self(), :tick, state.tick_ms)
    {:noreply, state}
  end

  # Measured, not assumed: a late timer moves the goat as far as the time it took.
  def handle_info(:goat, state) do
    now = now()
    {rooms, caught} = Rooms.step_goats(state.rooms, now - state.goat_at, now)
    frame = JSON.encode!([nil, nil, @topic, "caught", %{}])

    for pid <- caught, do: send(pid, {:caught, frame})

    Process.send_after(self(), :goat, state.goat_ms)
    {:noreply, %{state | rooms: rooms, goat_at: now}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state), do: {:noreply, drop(state, pid)}

  defp drop(state, pid) do
    state = %{state | ghosts: MapSet.delete(state.ghosts, pid)}

    case Map.pop(state.monitors, pid) do
      {nil, _monitors} ->
        %{state | rooms: Rooms.leave(state.rooms, pid)}

      {ref, monitors} ->
        Process.demonitor(ref, [:flush])
        %{state | rooms: Rooms.leave(state.rooms, pid), monitors: monitors}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
