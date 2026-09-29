defmodule Raycaster.OmenTest do
  use ExUnit.Case, async: true

  alias Raycaster.{Omen, SK6812}

  @cell 256
  @me %{x: 5 * @cell, y: 5 * @cell, a: 0}

  defp goat(cells, hunting \\ false), do: {5 * @cell + cells * @cell, 5 * @cell, hunting}

  test "no goat is nothing to dread" do
    assert Omen.level(@me, nil) == 0
  end

  test "the nearer the goat, the worse" do
    assert Omen.level(@me, goat(10)) == 0
    assert Omen.level(@me, goat(6)) == 1
    assert Omen.level(@me, goat(3)) == 2
    assert Omen.level(@me, goat(1)) == 2
    assert Omen.level(@me, goat(1, true)) == 3
  end

  test "it counts both ways across the map" do
    assert Omen.level(@me, {5 * @cell + 2 * @cell, 5 * @cell + 2 * @cell, false}) == 2
    assert Omen.level(@me, {5 * @cell - 5 * @cell, 5 * @cell - 5 * @cell, false}) == 0
  end

  test "every pattern is four dim colours a frame, and the lively ones change" do
    for level <- [0, 1, 2, 3, :caught] do
      {ms, frames} = Omen.pattern(level)
      assert ms == :infinity or ms >= 100

      for pixels <- frames do
        assert length(pixels) == 4
        for {r, g, b} <- pixels, do: assert(Enum.all?([r, g, b], &(&1 in 0..64)))
      end

      if ms != :infinity, do: assert(length(Enum.uniq(frames)) > 1)
    end
  end

  test "a frame is twelve bits per colour byte's worth of SPI bytes, and the latch" do
    frame = SK6812.encode([{255, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 1}])

    assert byte_size(frame) == 4 * 3 * 4 + 40
    # Green first: the first LED's green is zero, its red all ones.
    assert binary_part(frame, 0, 8) == <<0x88, 0x88, 0x88, 0x88, 0xCC, 0xCC, 0xCC, 0xCC>>
    assert binary_part(frame, 44, 4) == <<0x88, 0x88, 0x88, 0x8C>>
  end
end
