defmodule Relay.RoomsTest do
  use ExUnit.Case, async: true

  alias Relay.Rooms

  defp join_all(state, members) do
    Enum.reduce(members, {state, %{}}, fn member, {state, places} ->
      {state, place} = Rooms.join(state, member)
      {state, Map.put(places, member, place)}
    end)
  end

  describe "join/2" do
    test "the first player gets room 1, slot 1" do
      assert {_state, {1, 1}} = Rooms.join(Rooms.new(), :a)
    end

    test "players fill a room a slot at a time" do
      {_state, places} = join_all(Rooms.new(), [:a, :b, :c])

      assert places == %{a: {1, 1}, b: {1, 2}, c: {1, 3}}
    end

    test "the ninth player starts room 2, and nobody is ever refused" do
      {state, places} = join_all(Rooms.new(8), Enum.to_list(1..9))

      assert places[8] == {1, 8}
      assert places[9] == {2, 1}
      assert Rooms.counts(state) == [{1, 8}, {2, 1}]
    end

    test "a room is capped at what it was made with" do
      {state, _places} = join_all(Rooms.new(2), Enum.to_list(1..5))

      assert Rooms.counts(state) == [{1, 2}, {2, 2}, {3, 1}]
    end

    test "joining twice changes nothing" do
      {state, place} = Rooms.join(Rooms.new(), :a)

      assert {^state, ^place} = Rooms.join(state, :a)
    end

    test "a place that was left is the next one given, the lowest room and slot" do
      {state, _places} = join_all(Rooms.new(2), [:a, :b, :c])
      state = Rooms.leave(state, :a)

      assert {_state, {1, 1}} = Rooms.join(state, :d)
    end
  end

  describe "leave/2" do
    test "an empty room is forgotten, and its number can come round again" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.leave(state, :a)

      assert Rooms.rooms(state) == []
      assert {_state, {1, 1}} = Rooms.join(state, :b)
    end

    test "leaving without having joined changes nothing" do
      state = Rooms.new()

      assert Rooms.leave(state, :nobody) == state
    end

    test "room 1 emptying does not close room 2" do
      {state, _places} = join_all(Rooms.new(1), [:a, :b])
      state = Rooms.leave(state, :a)

      assert Rooms.counts(state) == [{2, 1}]
    end
  end

  describe "move/5 and snapshot/3" do
    test "a player is in the snapshot once it has said where it is" do
      {state, _place} = Rooms.join(Rooms.new(), :a)

      assert Rooms.snapshot(state, 1, 0) == []
      assert Rooms.snapshot(Rooms.move(state, :a, 300, 400, 0), 1, 0) == [[1, 300, 400]]
    end

    test "the snapshot is in slot order and only for that room" do
      {state, _places} = join_all(Rooms.new(2), [:a, :b, :c])

      state =
        state
        |> Rooms.move(:b, 20, 21, 0)
        |> Rooms.move(:a, 10, 11, 0)
        |> Rooms.move(:c, 30, 31, 0)

      assert Rooms.snapshot(state, 1, 0) == [[1, 10, 11], [2, 20, 21]]
      assert Rooms.snapshot(state, 2, 0) == [[1, 30, 31]]
      assert Rooms.snapshot(state, 3, 0) == []
    end

    test "someone quiet for five seconds is left out, but stays in the room" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.move(state, :a, 1, 2, 1_000)

      assert Rooms.snapshot(state, 1, 5_999) == [[1, 1, 2]]
      assert Rooms.snapshot(state, 1, 6_000) == []
      assert Rooms.counts(state) == [{1, 1}]
    end

    test "the last position is the one that counts" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = state |> Rooms.move(:a, 1, 2, 0) |> Rooms.move(:a, 3, 4, 300)

      assert Rooms.snapshot(state, 1, 300) == [[1, 3, 4]]
    end

    test "a second position within 200 ms is ignored, one after it is taken" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.move(state, :a, 1, 1, 1_000)

      assert Rooms.snapshot(Rooms.move(state, :a, 2, 2, 1_199), 1, 1_199) == [[1, 1, 1]]
      assert Rooms.snapshot(Rooms.move(state, :a, 2, 2, 1_200), 1, 1_200) == [[1, 2, 2]]
    end

    test "a position outside the map, or not a whole number, is ignored, well past the 200 ms gap" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.move(state, :a, 100, 100, 0)

      for {x, y} <- [
            {-1, 5},
            {5, -1},
            {4_096, 5},
            {5, 4_096},
            {1.5, 5},
            {"5", 5},
            {nil, 5},
            {5, :x}
          ] do
        assert Rooms.move(state, :a, x, y, 300) == state
      end

      assert Rooms.snapshot(Rooms.move(state, :a, 4_095, 0, 300), 1, 300) == [[1, 4_095, 0]]
    end

    test "someone who never joined cannot be moved into a room" do
      state = Rooms.new()

      assert Rooms.move(state, :stranger, 1, 2, 0) == state
    end
  end

  test "members/2 says who is in a room, and in which slot" do
    {state, _places} = join_all(Rooms.new(2), [:a, :b, :c])

    assert Enum.sort(Rooms.members(state, 1)) == [a: 1, b: 2]
    assert Rooms.members(state, 2) == [c: 1]
    assert Rooms.members(state, 9) == []
  end

  describe "the goat" do
    # A player standing on the goat, heard at `now`.
    defp on_the_goat(state, member, now) do
      [x, y, _hunting] = Rooms.goat(state, 1)
      Rooms.move(state, member, x, y, now)
    end

    test "every room has one, far from the start, wandering" do
      {state, _place} = Rooms.join(Rooms.new(), :a)

      assert [x, y, 0] = Rooms.goat(state, 1)
      assert x + y >= 20 * 256
      assert Rooms.goat(state, 2) == nil
    end

    test "goes when its room does" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.leave(state, :a)

      assert Rooms.goat(state, 1) == nil
    end

    test "catches whoever it reaches, who is then out of the snapshot and not listened to" do
      {state, _places} = join_all(Rooms.new(), [:a, :b])
      state = state |> on_the_goat(:a, 0) |> Rooms.move(:b, 384, 384, 0)

      {state, caught} = Rooms.step_goats(state, 100, 100)

      assert caught == [:a]
      assert Rooms.out?(state, :a)
      refute Rooms.out?(state, :b)
      assert [[2, 384, 384]] = Rooms.snapshot(state, 1, 100)

      state = Rooms.move(state, :a, 384, 384, 1_000)
      assert [[2, 384, 384]] = Rooms.snapshot(state, 1, 1_000)
    end

    test "does not catch the quiet, or anyone who has not said where they are" do
      {state, _places} = join_all(Rooms.new(), [:a, :b])
      state = on_the_goat(state, :a, 0)

      assert {_state, []} = Rooms.step_goats(state, 100, 10_000)
    end

    test "after a respawn a player is back, and safe for a while" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      {state, [:a]} = state |> on_the_goat(:a, 0) |> Rooms.step_goats(100, 100)

      state = Rooms.respawn(state, :a, 1_000)
      refute Rooms.out?(state, :a)
      assert Rooms.snapshot(state, 1, 1_000) == []

      state = on_the_goat(state, :a, 1_500)
      assert {state, []} = Rooms.step_goats(state, 100, 2_000)
      assert [[1, _x, _y]] = Rooms.snapshot(state, 1, 2_000)

      state = on_the_goat(state, :a, 3_900)
      assert {_state, [:a]} = Rooms.step_goats(state, 100, 4_000)
    end

    test "a respawn from someone who is not out changes nothing" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.move(state, :a, 384, 384, 0)

      assert Rooms.respawn(state, :a, 100) == state
      assert Rooms.respawn(state, :nobody, 100) == state
    end

    test "is calm until someone has lasted thirty seconds, and calm again once they are out" do
      {state, _places} = join_all(Rooms.new(), [:a, :b])
      state = state |> Rooms.move(:a, 384, 384, 0) |> Rooms.move(:b, 384, 384, 20_000)
      players = fn state -> state.rooms[1] end

      assert Rooms.pace(players.(state), 29_000) == :calm

      state = Rooms.move(state, :a, 390, 384, 29_500)
      assert Rooms.pace(players.(state), 30_000) == :fast

      # :a is caught: only :b, twenty seconds in, is left.
      state = put_in(state, [:rooms, 1, 1, :out], true)
      assert Rooms.pace(players.(state), 30_000) == :calm
    end

    test "is faster still once someone has lasted a minute" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.move(state, :a, 384, 384, 0) |> Rooms.move(:a, 390, 384, 59_000)

      assert Rooms.pace(state.rooms[1], 59_500) == :fast
      assert Rooms.pace(state.rooms[1], 60_000) == :faster
    end

    test "coming back starts the thirty seconds again" do
      {state, _place} = Rooms.join(Rooms.new(), :a)
      state = Rooms.move(state, :a, 384, 384, 0)
      state = put_in(state, [:rooms, 1, 1, :out], true)
      state = state |> Rooms.respawn(:a, 40_000) |> Rooms.move(:a, 384, 384, 41_000)

      assert Rooms.pace(state.rooms[1], 45_000) == :calm
      state = Rooms.move(state, :a, 390, 384, 70_000)
      assert Rooms.pace(state.rooms[1], 71_000) == :fast
    end
  end
end
