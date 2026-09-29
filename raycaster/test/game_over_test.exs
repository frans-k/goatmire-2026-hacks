defmodule Raycaster.GameOverTest do
  use ExUnit.Case, async: true

  alias Raycaster.{Engine, GameOver}

  @width 320
  @height 240

  defp items(survived \\ 42), do: GameOver.items(Engine.grid(), survived, @width, @height)

  test "the text comes first, on top, and says how long you lasted" do
    texts = for {:text, _x, _y, _font, _colour, _back, text} <- items(), do: text

    assert texts == ["GAME OVER", "The evil goat got you", "You lasted 42 s", "Press any key"]
    assert match?({:text, _, _, _, _, _, _}, hd(items()))
  end

  test "the text is centred and on the screen" do
    for {:text, x, y, _font, _colour, _back, text} <- items(1234) do
      assert x >= 0 and x + byte_size(text) * 8 <= @width
      assert abs(x + div(byte_size(text) * 8, 2) - div(@width, 2)) <= 4
      assert y >= 0 and y + 16 <= @height
    end
  end

  test "the goat is there, close and hunting, between the lines of text" do
    rects = for {:rect, _x, _y, _w, _h, _c} = rect <- items(), do: rect

    assert Enum.count(rects, fn {:rect, _x, _y, _w, _h, c} -> c == 0xFF2010 end) == 2
    goat = Enum.drop(rects, -2)
    assert length(goat) == 13

    for {:rect, x, y, w, h, _c} <- goat do
      assert x >= 0 and x + w <= @width
      assert y >= 70 and y + h <= @height - 44
    end
  end

  test "the background is last, behind everything" do
    assert List.last(items()) == {:rect, 0, 0, @width, @height, 0x3A0808}
  end
end
