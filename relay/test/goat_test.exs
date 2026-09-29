defmodule Relay.GoatTest do
  use ExUnit.Case, async: true

  alias Relay.{Goat, Level}

  defp at(cx, cy), do: Level.centre({cx, cy})

  # Steps the goat `n` times, 100 ms apart, with the players standing still.
  # Returns the goat and everyone caught.
  defp run(goat, players, n, now \\ 0) do
    Enum.reduce(1..n, {goat, []}, fn i, {goat, caught} ->
      {goat, more} = Goat.step(goat, players, 100, now + i * 100)
      {goat, caught ++ more}
    end)
  end

  defp cell(goat), do: Level.cell(goat.x, goat.y)

  test "it starts in the middle of its cell, wandering" do
    assert Goat.where(Goat.new({14, 14}, 1)) == {14 * 256 + 128, 14 * 256 + 128, false}
  end

  test "wandering, it never walks into a wall, however long it goes" do
    for seed <- 1..5 do
      Enum.reduce(1..600, Goat.new({14, 14}, seed), fn i, goat ->
        {goat, []} = Goat.step(goat, [], 100, i * 100)
        assert Level.open?(goat.x, goat.y)
        goat
      end)
    end
  end

  test "it gets somewhere, wandering" do
    {goat, []} = run(Goat.new({14, 14}, 7), [], 200)
    assert cell(goat) != {14, 14}
  end

  test "it hunts someone in plain sight" do
    {x, y} = at(10, 1)
    {goat, []} = Goat.step(Goat.new({14, 1}, 1), [{:a, x, y}], 100, 100)

    assert goat.mode == :hunt
    assert goat.target == :a
    assert {_x, _y, true} = Goat.where(goat)
  end

  test "it does not see through walls" do
    # (8, 2) is behind the wall at (3..6, 2) from (2, 2).
    {x, y} = at(2, 2)
    {goat, []} = Goat.step(Goat.new({8, 2}, 1), [{:a, x, y}], 100, 100)

    assert goat.mode == :wander
  end

  test "nor farther than eight cells" do
    {x, y} = at(1, 9)
    {goat, []} = Goat.step(Goat.new({14, 9}, 1), [{:a, x, y}], 100, 100)

    assert goat.mode == :wander
  end

  test "it runs someone in sight down and catches them" do
    {x, y} = at(9, 1)
    {goat, caught} = run(Goat.new({14, 1}, 1), [{:a, x, y}], 30)

    assert caught != []
    assert Enum.uniq(caught) == [:a]
    assert cell(goat) == {9, 1}
  end

  test "the nearest it sees is the one it hunts" do
    {near_x, near_y} = at(11, 1)
    {far_x, far_y} = at(7, 1)

    {goat, _caught} =
      Goat.step(Goat.new({14, 1}, 1), [{:far, far_x, far_y}, {:near, near_x, near_y}], 100, 100)

    assert goat.target == :near
  end

  test "losing sight of them, it goes where they were, searches, then wanders again" do
    {x, y} = at(12, 1)
    {goat, []} = Goat.step(Goat.new({14, 1}, 1), [{:a, x, y}], 100, 100)
    assert goat.mode == :hunt

    # Gone: say, round the corner behind a wall.
    {goat, []} = Goat.step(goat, [], 100, 200)
    assert goat.mode == :search

    {goat, []} = run(goat, [], 20, 200)
    assert goat.mode == :search
    assert cell(goat) == {12, 1}

    {goat, []} = run(goat, [], 30, 2_200)
    assert goat.mode == :wander
  end

  test "searching, it walks round a wall to where it lost them" do
    # From (7, 2) to (2, 2), with the wall at (3..6, 2) between: up, along row 1,
    # and down, about seven cells, never through the wall.
    goat = %{Goat.new({7, 2}, 1) | mode: :search, goal: at(2, 2), lost_at: 1_000}

    goat =
      Enum.reduce(1..45, goat, fn i, goat ->
        {goat, []} = Goat.step(goat, [], 100, i * 100)
        assert Level.open?(goat.x, goat.y)
        goat
      end)

    assert cell(goat) == {2, 2}
    assert goat.mode == :search
  end
end
