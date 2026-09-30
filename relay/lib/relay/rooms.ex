defmodule Relay.Rooms do
  @moduledoc """
  Who is in which room, and where they stand. Plain data, no processes.

  A room holds at most `max` players. `join/2` puts a player in the lowest-numbered
  room that has a free place, and makes a new room when every one is full, so
  nobody chooses a room and none is ever refused. A player gets the lowest free
  slot in the room, 1 to `max`, which is all the badges ever need to know about
  each other: the slot is who they are and what colour they are drawn in.

  A room is forgotten when its last player leaves. A player who has not said where
  they are for `@ttl_ms` is left out of the snapshot, but stays in the room: they
  are only quiet, and the connection knows when they are gone.

  Every room has an evil goat (`Relay.Goat`), made with the room as far from where
  the badges start as the map allows. `step_goats/3` moves them all and says whom
  they caught. A caught player is out: left out of the snapshot and not listened
  to until they `respawn/3`, and then safe from the goat for `@grace_ms`, while
  they find their feet at the start again.

  The goat starts calm, goes fast while anyone in its room has lasted
  `@fast_after_ms`, and faster still while anyone has lasted `@faster_after_ms`,
  counted from the first position they said after joining or coming back. It
  goes by whoever has lasted longest of those still in play, so once they are
  caught, or gone, it slows down again.
  """

  alias Relay.{Goat, Level}

  import Bitwise

  @max 8
  @ttl_ms 5_000
  # A badge that talks faster than this is not listened to, whatever it says.
  @min_gap_ms 200
  # The badges' map is 16 by 16 cells, 256 to a cell.
  @limit 4_096
  @grace_ms 3_000
  @fast_after_ms 30_000
  @faster_after_ms 60_000
  # Where every badge starts, the cell the goat is put farthest from.
  @start {1, 1}

  @type member :: term
  @type t :: %{
          max: pos_integer,
          rooms: %{pos_integer => %{pos_integer => map}},
          where: %{member => {pos_integer, pos_integer}},
          goats: %{pos_integer => Goat.t()}
        }

  @spec new(pos_integer) :: t
  def new(max \\ @max), do: %{max: max, rooms: %{}, where: %{}, goats: %{}}

  @doc "Puts `member` in a room. Joining twice changes nothing."
  @spec join(t, member) :: {t, {pos_integer, pos_integer}}
  def join(state, member) do
    case state.where do
      %{^member => place} ->
        {state, place}

      _not_yet ->
        room = room_with_space(state)
        slot = free_slot(Map.get(state.rooms, room, %{}), state.max)
        entry = %{x: nil, y: nil, seen: nil, out: false, safe_until: nil, since: nil}

        state = %{
          state
          | rooms: Map.update(state.rooms, room, %{slot => entry}, &Map.put(&1, slot, entry)),
            where: Map.put(state.where, member, {room, slot}),
            goats: Map.put_new_lazy(state.goats, room, &new_goat/0)
        }

        {state, {room, slot}}
    end
  end

  @doc "Takes `member` out. A room with nobody left is dropped."
  @spec leave(t, member) :: t
  def leave(state, member) do
    case Map.pop(state.where, member) do
      {nil, _where} ->
        state

      {{room, slot}, where} ->
        players = state.rooms |> Map.fetch!(room) |> Map.delete(slot)

        if players == %{} do
          %{
            state
            | rooms: Map.delete(state.rooms, room),
              where: where,
              goats: Map.delete(state.goats, room)
          }
        else
          %{state | rooms: Map.put(state.rooms, room, players), where: where}
        end
    end
  end

  @doc """
  Records where `member` stands, as heard at `now` (milliseconds). Anything that
  is not a whole number inside the map is ignored, and so is a second position
  within 200 ms of the last: the badges' word is not taken for it. So is anything
  from a player who is out.
  """
  @spec move(t, member, term, term, integer) :: t
  def move(state, member, x, y, now)
      when is_integer(x) and is_integer(y) and x >= 0 and x < @limit and y >= 0 and y < @limit do
    case state.where do
      %{^member => {room, slot}} ->
        case get_in(state, [:rooms, room, slot]) do
          %{out: true} ->
            state

          %{seen: seen} when is_integer(seen) and now - seen < @min_gap_ms ->
            state

          entry ->
            since = entry.since || now
            put_in(state, [:rooms, room, slot], %{entry | x: x, y: y, seen: now, since: since})
        end

      _unknown ->
        state
    end
  end

  def move(state, _member, _x, _y, _now), do: state

  @doc "Everyone in `room` who has said where they are lately and is not out, as `[slot, x, y]`."
  @spec snapshot(t, pos_integer, integer) :: [[integer]]
  def snapshot(state, room, now) do
    state.rooms
    |> Map.get(room, %{})
    |> Enum.flat_map(fn
      {slot, %{x: x, y: y, seen: seen, out: false}}
      when is_integer(seen) and now - seen < @ttl_ms ->
        [[slot, x, y]]

      _quiet ->
        []
    end)
    |> Enum.sort()
  end

  @doc "Where the goat of `room` stands, as `[x, y, hunting]` with hunting 1 or 0, or nil."
  @spec goat(t, pos_integer) :: [integer] | nil
  def goat(state, room) do
    case Map.get(state.goats, room) do
      nil ->
        nil

      goat ->
        {x, y, hunting} = Goat.where(goat)
        [x, y, if(hunting, do: 1, else: 0)]
    end
  end

  @doc """
  Moves every room's goat on by `dt_ms`, after the players it may hunt: those who
  have said where they are lately, are not out, and are not safe. Whoever it
  catches is out. Returns the members caught.
  """
  @spec step_goats(t, non_neg_integer, integer) :: {t, [member]}
  def step_goats(state, dt_ms, now) do
    Enum.reduce(state.goats, {state, []}, fn {room, goat}, {state, caught} ->
      players = Map.get(state.rooms, room, %{})

      prey =
        for {slot, %{x: x, y: y, seen: seen, out: false} = entry} <- players,
            is_integer(seen) and now - seen < @ttl_ms,
            entry.safe_until == nil or now >= entry.safe_until,
            do: {slot, x, y}

      {goat, slots} = Goat.step(goat, prey, dt_ms, now, pace(players, now))

      players =
        Enum.reduce(slots, players, fn slot, players ->
          Map.update!(players, slot, &%{&1 | out: true})
        end)

      members = for {member, slot} <- members(state, room), slot in slots, do: member

      state = %{
        state
        | goats: Map.put(state.goats, room, goat),
          rooms: Map.put(state.rooms, room, players)
      }

      {state, members ++ caught}
    end)
  end

  @doc """
  Brings `member` back after being caught, at the start with no position until it
  says one, and safe from the goat until `@grace_ms` after `now`. Anyone not out
  is left as they are.
  """
  @spec respawn(t, member, integer) :: t
  def respawn(state, member, now) do
    with %{^member => {room, slot}} <- state.where,
         %{out: true} = entry <- get_in(state, [:rooms, room, slot]) do
      entry = %{
        entry
        | out: false,
          x: nil,
          y: nil,
          seen: nil,
          since: nil,
          safe_until: now + @grace_ms
      }

      put_in(state, [:rooms, room, slot], entry)
    else
      _not_out -> state
    end
  end

  @doc "How fast the goat of a room with these players goes, by whoever of them has lasted longest."
  @spec pace(%{pos_integer => map}, integer) :: :calm | :fast | :faster
  def pace(players, now) do
    longest =
      players
      |> Enum.flat_map(fn {_slot, entry} ->
        if not entry.out and is_integer(entry.since) and is_integer(entry.seen) and
             now - entry.seen < @ttl_ms,
           do: [now - entry.since],
           else: []
      end)
      |> Enum.max(fn -> 0 end)

    cond do
      longest >= @faster_after_ms -> :faster
      longest >= @fast_after_ms -> :fast
      true -> :calm
    end
  end

  @doc "Whether `member` has been caught and not come back yet."
  @spec out?(t, member) :: boolean
  def out?(state, member) do
    case state.where do
      %{^member => {room, slot}} -> get_in(state, [:rooms, room, slot, :out]) == true
      _unknown -> false
    end
  end

  @doc "The rooms there are, with how many are in each."
  @spec counts(t) :: [{pos_integer, non_neg_integer}]
  def counts(state) do
    state.rooms |> Enum.map(fn {room, players} -> {room, map_size(players)} end) |> Enum.sort()
  end

  @doc "The members of `room`, with their slots."
  @spec members(t, pos_integer) :: [{member, pos_integer}]
  def members(state, room) do
    for {member, {^room, slot}} <- state.where, do: {member, slot}
  end

  @doc "How many players there are, in all rooms."
  @spec count(t) :: non_neg_integer
  def count(state), do: map_size(state.where)

  @doc "Whether `member` is in a room."
  @spec member?(t, member) :: boolean
  def member?(state, member), do: Map.has_key?(state.where, member)

  @doc "Every room that has anyone in it."
  @spec rooms(t) :: [pos_integer]
  def rooms(state), do: state.rooms |> Map.keys() |> Enum.sort()

  defp room_with_space(state) do
    full = fn room -> map_size(Map.fetch!(state.rooms, room)) >= state.max end

    case Enum.find(rooms(state), fn room -> not full.(room) end) do
      nil -> first_unused(state, 1)
      room -> room
    end
  end

  defp new_goat, do: Goat.new(Level.farthest_from(@start), :rand.uniform(1 <<< 30))

  defp first_unused(state, n),
    do: if(Map.has_key?(state.rooms, n), do: first_unused(state, n + 1), else: n)

  defp free_slot(players, max) do
    Enum.find(1..max, fn slot -> not Map.has_key?(players, slot) end)
  end
end
