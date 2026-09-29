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
  """

  @max 8
  @ttl_ms 5_000
  # A badge that talks faster than this is not listened to, whatever it says.
  @min_gap_ms 200
  # The badges' map is 16 by 16 cells, 256 to a cell.
  @limit 4_096

  @type member :: term
  @type t :: %{
          max: pos_integer,
          rooms: %{pos_integer => %{pos_integer => map}},
          where: %{member => {pos_integer, pos_integer}}
        }

  @spec new(pos_integer) :: t
  def new(max \\ @max), do: %{max: max, rooms: %{}, where: %{}}

  @doc "Puts `member` in a room. Joining twice changes nothing."
  @spec join(t, member) :: {t, {pos_integer, pos_integer}}
  def join(state, member) do
    case state.where do
      %{^member => place} ->
        {state, place}

      _not_yet ->
        room = room_with_space(state)
        slot = free_slot(Map.get(state.rooms, room, %{}), state.max)
        entry = %{x: nil, y: nil, seen: nil}

        state = %{
          state
          | rooms: Map.update(state.rooms, room, %{slot => entry}, &Map.put(&1, slot, entry)),
            where: Map.put(state.where, member, {room, slot})
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

        rooms =
          if players == %{},
            do: Map.delete(state.rooms, room),
            else: Map.put(state.rooms, room, players)

        %{state | rooms: rooms, where: where}
    end
  end

  @doc """
  Records where `member` stands, as heard at `now` (milliseconds). Anything that
  is not a whole number inside the map is ignored, and so is a second position
  within 200 ms of the last: the badges' word is not taken for it.
  """
  @spec move(t, member, term, term, integer) :: t
  def move(state, member, x, y, now)
      when is_integer(x) and is_integer(y) and x >= 0 and x < @limit and y >= 0 and y < @limit do
    case state.where do
      %{^member => {room, slot}} ->
        case get_in(state, [:rooms, room, slot, :seen]) do
          seen when is_integer(seen) and now - seen < @min_gap_ms ->
            state

          _quiet ->
            put_in(state, [:rooms, room, slot], %{x: x, y: y, seen: now})
        end

      _unknown ->
        state
    end
  end

  def move(state, _member, _x, _y, _now), do: state

  @doc "Everyone in `room` who has said where they are lately, as `[slot, x, y]`."
  @spec snapshot(t, pos_integer, integer) :: [[integer]]
  def snapshot(state, room, now) do
    state.rooms
    |> Map.get(room, %{})
    |> Enum.flat_map(fn
      {slot, %{x: x, y: y, seen: seen}} when is_integer(seen) and now - seen < @ttl_ms ->
        [[slot, x, y]]

      _quiet ->
        []
    end)
    |> Enum.sort()
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

  defp first_unused(state, n),
    do: if(Map.has_key?(state.rooms, n), do: first_unused(state, n + 1), else: n)

  defp free_slot(players, max) do
    Enum.find(1..max, fn slot -> not Map.has_key?(players, slot) end)
  end
end
