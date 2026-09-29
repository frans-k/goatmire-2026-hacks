defmodule MyHack.Face do
  @moduledoc """
  Pixel-art faces for the display, drawn from rectangles.

  A face is ten rows of ten cells, `#` for a lit one, drawn at `@cell` pixels
  a cell. Adding an expression is adding an entry here (and to the list in
  `scripts/claude_chat.exs`, so Claude knows it exists).
  """

  @cell 4
  @size 10 * @cell

  @faces %{
    "neutral" => [
      "..........",
      "..........",
      "..##..##..",
      "..##..##..",
      "..........",
      "..........",
      "...####...",
      "..........",
      "..........",
      ".........."
    ],
    "happy" => [
      "..........",
      "..........",
      "..##..##..",
      "..##..##..",
      "..........",
      ".#......#.",
      "..#....#..",
      "...####...",
      "..........",
      ".........."
    ],
    "sad" => [
      "..........",
      "..........",
      "..##..##..",
      "..##..##..",
      "..........",
      "..........",
      "...####...",
      "..#....#..",
      ".#......#.",
      ".........."
    ],
    "surprised" => [
      "..........",
      "..##..##..",
      "..##..##..",
      "..##..##..",
      "..........",
      "...####...",
      "...#..#...",
      "...#..#...",
      "...####...",
      ".........."
    ],
    "thinking" => [
      "..........",
      "..........",
      "......##..",
      "..##..##..",
      "..........",
      "..........",
      ".....###..",
      "..........",
      "..........",
      ".........."
    ],
    "sleepy" => [
      "..........",
      "..........",
      "..........",
      "..##..##..",
      "..........",
      "..........",
      "....##....",
      "..........",
      "..........",
      ".........."
    ],
    "love" => [
      "..........",
      "..........",
      ".#.#..#.#.",
      ".###..###.",
      "..#....#..",
      "..........",
      ".#......#.",
      "..#....#..",
      "...####...",
      ".........."
    ]
  }

  def size, do: @size

  def known?(name), do: Map.has_key?(@faces, name)

  # Display-list items for the face at x, y. An unknown name draws nothing.
  def items(name, x, y, colour) do
    case Map.fetch(@faces, name) do
      {:ok, rows} -> rows(rows, 0, x, y, colour)
      :error -> []
    end
  end

  defp rows([], _row, _x, _y, _colour), do: []

  defp rows([cells | rest], row, x, y, colour) do
    runs(cells, 0, x, y + row * @cell, colour, rows(rest, row + 1, x, y, colour))
  end

  # Neighbouring lit cells become one rectangle instead of several.
  defp runs(<<>>, _col, _x, _y, _colour, acc), do: acc

  defp runs(<<".", rest::binary>>, col, x, y, colour, acc),
    do: runs(rest, col + 1, x, y, colour, acc)

  defp runs(<<"#", _::binary>> = cells, col, x, y, colour, acc) do
    {length, rest} = lit(cells, 0)
    rect = {:rect, x + col * @cell, y, length * @cell, @cell, colour}

    [rect | runs(rest, col + length, x, y, colour, acc)]
  end

  defp lit(<<"#", rest::binary>>, count), do: lit(rest, count + 1)
  defp lit(rest, count), do: {count, rest}
end
