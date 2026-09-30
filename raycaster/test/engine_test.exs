defmodule Raycaster.EngineTest do
  # The engine is plain integer arithmetic, so it can be checked on the laptop
  # with `mix test`; only the display and keyboard need the badge.
  use ExUnit.Case, async: true

  alias Raycaster.Engine

  @width 320
  @height 240
  @ceiling 0x202838
  @floor 0x504030

  # The player starts in the corner cell (1.5, 1.5), and one map cell is 256.
  @cell 256

  defp frame(player), do: Engine.frame(Engine.grid(), player, @width, @height)

  defp walls(items),
    do: for({:rect, x, y, w, h, c} <- items, c not in [@ceiling, @floor], do: {x, y, w, h})

  # The wall rectangle covering the middle of the screen, which is where the
  # ray runs straight along the player's direction.
  defp centre_wall(player) do
    Enum.find(walls(frame(player)), fn {x, _y, w, _h} -> x <= 160 and 160 < x + w end)
  end

  describe "wall height in the middle column is screen height / distance" do
    test "facing the west wall half a cell away fills the screen" do
      # Height would be 480, clamped to the screen.
      assert {_x, 0, _w, 240} = centre_wall(%{Engine.new() | a: 128 * 256})
    end

    test "facing the far east wall 13.5 cells away" do
      # 240 * 256 / (13.5 * 256), rounded down.
      assert {_x, top, _w, 17} = centre_wall(%{Engine.new() | a: 0})
      assert top == div(240 - 17, 2)
    end

    test "standing closer makes the same wall taller" do
      near = %{x: 12 * @cell + 128, y: 384, a: 0}

      # 2.5 cells to the wall at x = 15: 240 * 256 / 640 = 96.
      assert {_x, _top, _w, 96} = centre_wall(near)
    end

    test "looking along y gives the same distance as along x" do
      assert {_, _, _, 17} = centre_wall(%{Engine.new() | a: 64 * 256})
    end
  end

  describe "frame/4" do
    test "everything stays on the screen and the list stays small" do
      for x <- [1, 5, 8, 14], y <- [1, 6, 13], a <- [0, 37, 90, 150, 222] do
        items = frame(%{x: x * @cell + 100, y: y * @cell + 100, a: a * 256})

        for {:rect, rx, ry, w, h, _colour} <- items do
          assert rx >= 0 and ry >= 0 and w > 0 and h > 0
          assert rx + w <= @width and ry + h <= @height
        end

        # At most one rectangle per column, plus floor and ceiling.
        assert length(items) <= Engine.cols() + 2
      end
    end

    test "floor and ceiling are drawn behind the walls" do
      items = frame(Engine.new())

      # The first item is on top and the last is drawn first.
      assert [{:rect, 0, 0, @width, 120, @ceiling}, {:rect, 0, 120, @width, 120, @floor} | _] =
               Enum.reverse(items)
    end

    test "farther walls are darker" do
      colour_at = fn a ->
        {:rect, _x, _y, _w, _h, colour} =
          Enum.find(frame(%{Engine.new() | a: a}), fn {:rect, x, _, w, _, c} ->
            c not in [@ceiling, @floor] and x <= 160 and 160 < x + w
          end)

        colour
      end

      brightness = fn c ->
        Bitwise.band(c, 0xFF) + Bitwise.band(Bitwise.bsr(c, 8), 0xFF) + Bitwise.bsr(c, 16)
      end

      # West wall is 0.5 cells away, east wall 13.5.
      assert brightness.(colour_at.(128 * 256)) > brightness.(colour_at.(0))
    end
  end

  describe "the fixed tour in Raycaster.Bench" do
    test "draws exactly the frames it drew before the speed work" do
      {expected, _binding} = Code.eval_file("test/tour_frames.exs")

      assert Enum.map(Raycaster.Bench.tour(), &frame/1) == expected
    end

    test "stands only on floor" do
      grid = Engine.grid()

      for %{x: x, y: y} <- Raycaster.Bench.tour() do
        assert elem(grid, div(y, @cell) * 16 + div(x, @cell)) == 0
      end
    end
  end

  describe "sprites/5" do
    @red 0xC83C32

    defp sprites(player, others),
      do: Engine.sprites(Engine.grid(), player, others, @width, @height)

    # A player in open floor, facing east along row 9.
    defp facing_east, do: %{x: 2 * @cell + 128, y: 9 * @cell + 128, a: 0}

    defp ahead(cells, across \\ 0) do
      {2 * @cell + 128 + cells * @cell, 9 * @cell + 128 + across, @red}
    end

    # The body, the wide rectangle of the two.
    defp body(items), do: Enum.max_by(items, fn {:rect, _x, _y, w, _h, _c} -> w end)
    defp centre({:rect, x, _y, w, _h, _c}), do: x + div(w, 2)

    test "nobody means nothing to draw" do
      assert sprites(facing_east(), []) == []
    end

    test "someone straight ahead is in the middle of the screen" do
      items = sprites(facing_east(), [ahead(4)])

      assert length(items) == 2
      assert abs(centre(body(items)) - div(@width, 2)) <= 1
    end

    test "someone off to one side is on that side" do
      right = sprites(facing_east(), [ahead(4, 100)])
      left = sprites(facing_east(), [ahead(4, -100)])

      assert centre(body(right)) > div(@width, 2)
      assert centre(body(left)) < div(@width, 2)
    end

    test "a farther figure is smaller, and stands on the same floor line" do
      {:rect, _x, _y, near_w, near_h, _c} = body(sprites(facing_east(), [ahead(2)]))
      {:rect, _x, _y, far_w, far_h, _c} = body(sprites(facing_east(), [ahead(8)]))

      assert near_w > far_w
      assert near_h > far_h
    end

    test "everything stays on the screen" do
      for cells <- [1, 3, 6, 10], across <- [-600, -200, 0, 200, 600] do
        for {:rect, x, y, w, h, _c} <- sprites(facing_east(), [ahead(cells, across)]) do
          assert x >= 0 and y >= 0 and w > 0 and h > 0
          assert x + w <= @width and y + h <= @height
        end
      end
    end

    test "someone behind the player is not drawn" do
      assert sprites(facing_east(), [{@cell + 128, 9 * @cell + 128, @red}]) == []
    end

    test "someone too close is not drawn" do
      assert sprites(facing_east(), [ahead(0) |> put_elem(0, 2 * @cell + 128 + 30)]) == []
    end

    test "someone behind a wall is not drawn, and is once the wall is out of the way" do
      # Row 2 has a wall at columns 3 to 6.
      player = %{x: 2 * @cell + 128, y: 2 * @cell + 128, a: 0}

      assert sprites(player, [{8 * @cell + 128, 2 * @cell + 128, @red}]) == []
      assert length(sprites(player, [{3 * @cell - 20, 2 * @cell + 128, @red}])) == 2
    end

    test "the nearest come first, since the first item is on top" do
      items = sprites(facing_east(), [ahead(8, 100), ahead(2), ahead(5, -100)])
      widths = for {:rect, _x, _y, w, _h, _c} <- items, w > 20, do: w

      assert length(items) == 6
      assert widths == Enum.sort(widths, :desc)
    end

    test "a distant figure is darker than a near one" do
      brightness = fn items ->
        {:rect, _x, _y, _w, _h, c} = body(items)
        Bitwise.band(c, 0xFF) + Bitwise.band(Bitwise.bsr(c, 8), 0xFF) + Bitwise.bsr(c, 16)
      end

      assert brightness.(sprites(facing_east(), [ahead(2)])) >
               brightness.(sprites(facing_east(), [ahead(9)]))
    end
  end

  describe "the goat in sprites/5" do
    @calm 0xE8B820
    @angry 0xFF2010

    defp goat(player, goats), do: Engine.sprites(Engine.grid(), player, goats, @width, @height)

    defp facing_east_again, do: %{x: 2 * @cell + 128, y: 9 * @cell + 128, a: 0}

    defp goat_ahead(cells, hunting \\ false, across \\ 0) do
      {:goat, 2 * @cell + 128 + cells * @cell, 9 * @cell + 128 + across, hunting}
    end

    defp colours(items), do: for({:rect, _x, _y, _w, _h, c} <- items, do: c)
    defp widest(items), do: Enum.max_by(items, fn {:rect, _x, _y, w, _h, _c} -> w end)

    test "near, it is thirteen rectangles in the middle of the screen" do
      items = goat(facing_east_again(), [goat_ahead(2)])
      {:rect, x, _y, w, _h, _c} = widest(items)

      assert length(items) == 13
      assert abs(x + div(w, 2) - div(@width, 2)) <= 2
    end

    test "far off, it is five" do
      assert length(goat(facing_east_again(), [goat_ahead(9)])) == 5
    end

    test "its eyes are yellow, and red while it hunts, and come first" do
      assert [@calm, @calm | rest] = colours(goat(facing_east_again(), [goat_ahead(3)]))
      refute @angry in rest

      assert [@angry, @angry | _rest] = colours(goat(facing_east_again(), [goat_ahead(3, true)]))
      assert [@angry, @angry | _rest] = colours(goat(facing_east_again(), [goat_ahead(9, true)]))
    end

    test "it stands on the same floor line as a player" do
      bottom = fn items ->
        items |> Enum.map(fn {:rect, _x, y, _w, h, _c} -> y + h end) |> Enum.max()
      end

      player = {2 * @cell + 128 + 4 * @cell, 9 * @cell + 128, 0xC83C32}

      assert abs(
               bottom.(goat(facing_east_again(), [goat_ahead(4)])) -
                 bottom.(goat(facing_east_again(), [player]))
             ) <= 1
    end

    test "everything stays on the screen" do
      for cells <- [1, 2, 3, 6, 10], across <- [-600, -200, 0, 200, 600], hunting <- [true, false] do
        for {:rect, x, y, w, h, _c} <- goat(facing_east_again(), [goat_ahead(cells, hunting, across)]) do
          assert x >= 0 and y >= 0 and w > 0 and h > 0
          assert x + w <= @width and y + h <= @height
        end
      end
    end

    test "it hides behind walls like anyone" do
      # Row 2 has a wall at columns 3 to 6.
      player = %{x: 2 * @cell + 128, y: 2 * @cell + 128, a: 0}

      assert goat(player, [{:goat, 8 * @cell + 128, 2 * @cell + 128, true}]) == []
    end

    test "a goat nearer than a player is drawn on top of them" do
      player = {2 * @cell + 128 + 5 * @cell, 9 * @cell + 128, 0xC83C32}
      items = goat(facing_east_again(), [player, goat_ahead(2, true)])

      assert [@angry, @angry | _rest] = colours(items)
      assert length(items) == 15
    end
  end

  describe "the map" do
    # Rays are not bounds checked and have no step limit: the outer wall is what
    # stops them.
    test "is closed all the way round" do
      grid = Engine.grid()
      border = for i <- 0..15, cell <- [{i, 0}, {i, 15}, {0, i}, {15, i}], uniq: true, do: cell

      for {x, y} <- border do
        assert elem(grid, y * 16 + x) != 0, "open border cell at #{x},#{y}"
      end
    end
  end

  describe "step/4" do
    test "holding forward moves along the direction" do
      moved = Engine.step(Engine.grid(), Engine.new(), ["Up"], 200)

      assert moved.x > Engine.new().x
      assert moved.y == Engine.new().y
    end

    test "turning changes only the angle, at a rate that does not depend on frame time" do
      one = Engine.step(Engine.grid(), Engine.new(), ["Right"], 1000)

      halves =
        Enum.reduce(1..10, Engine.new(), fn _, p ->
          Engine.step(Engine.grid(), p, ["Right"], 100)
        end)

      assert one.a == 40_000
      assert halves.a == 40_000
      assert {one.x, one.y} == {Engine.new().x, Engine.new().y}
    end

    test "walls stop the player, on each axis separately" do
      grid = Engine.grid()
      # Facing west, into the wall column x = 0, for long enough to cross it.
      west =
        Enum.reduce(1..50, %{Engine.new() | a: 128 * 256}, fn _, p ->
          Engine.step(grid, p, ["Up"], 100)
        end)

      # Never inside the wall cell (x < 256), with room for the player's radius.
      assert west.x >= @cell + 60

      # Walking diagonally into the corner slides along a wall instead of sticking.
      corner = %{x: @cell + 100, y: 2 * @cell, a: 96 * 256}
      slid = Enum.reduce(1..20, corner, fn _, p -> Engine.step(grid, p, ["Up"], 100) end)

      assert slid.x >= @cell + 60
      assert slid.y != corner.y
    end

    test "labels as charlists mean the same as binaries" do
      grid = Engine.grid()
      # Columns 9 to 14 are open in rows 8 to 10, so every direction can move.
      start = %{x: 11 * @cell + 128, y: 9 * @cell + 128, a: 0}

      for label <- ["Up", "S", "Q", "E", "D", "Left"] do
        binary = Engine.step(grid, start, [label], 200)

        assert Engine.step(grid, start, [String.to_charlist(label)], 200) == binary
        refute binary == start
      end
    end

    test "no keys held means no movement" do
      assert Engine.step(Engine.grid(), Engine.new(), [], 500) == Engine.new()
    end
  end

  describe "respawn/1" do
    test "without a goat it is the start, as a new player" do
      assert Engine.respawn(nil) == Engine.new()
    end

    test "a goat near the start sends the badge to the far corner, facing into the map" do
      assert %{x: 3456, y: 3456, a: 32_768} = Engine.respawn({500, 500, true})
    end

    test "a goat near the far corner leaves the badge at the start" do
      assert Engine.respawn({3400, 3400, false}) == Engine.new()
    end

    test "it is the same whether the goat is hunting or wandering" do
      assert Engine.respawn({500, 500, true}) == Engine.respawn({500, 500, false})
    end

    test "either place is open floor" do
      grid = Engine.grid()

      for goat <- [{500, 500, true}, {3400, 3400, true}] do
        %{x: x, y: y} = Engine.respawn(goat)
        assert elem(grid, div(y, 256) * 16 + div(x, 256)) == 0
      end
    end
  end
end
