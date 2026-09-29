defmodule Relay.LevelTest do
  use ExUnit.Case, async: true

  alias Relay.Level

  test "is the badges' map: the file the raycaster is built from" do
    assert Level.size() == 16
    refute Level.open_cell?({0, 0})
    assert Level.open_cell?({1, 1})
    # Row 2 has a wall at columns 3 to 6.
    refute Level.open_cell?({3, 2})
  end

  test "outside the map is wall" do
    refute Level.open_cell?({-1, 5})
    refute Level.open_cell?({16, 5})
  end

  test "sees along open floor, not through walls" do
    assert Level.visible?(1 * 256 + 128, 1 * 256 + 128, 14 * 256 + 128, 1 * 256 + 128)
    refute Level.visible?(2 * 256 + 128, 2 * 256 + 128, 8 * 256 + 128, 2 * 256 + 128)
  end

  test "the way round a wall starts with the right step" do
    # From (2, 2) to (7, 2), with the wall at (3..6, 2) between: round it, above or below.
    assert Level.next_cell({2, 2}, {7, 2}) in [{2, 1}, {2, 3}]
    assert Level.next_cell({2, 2}, {2, 2}) == nil
  end

  test "every open cell can be walked to from the start" do
    assert map_size(Level.distances({1, 1})) == length(Level.open_cells())
  end

  test "the farthest cell from the start is well away from it" do
    {cx, cy} = Level.farthest_from({1, 1})
    assert Level.open_cell?({cx, cy})
    assert cx + cy >= 20
  end
end
