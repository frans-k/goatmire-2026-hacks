defmodule MyHack.Keymap do
  @moduledoc """
  What each matrix position means, kept apart from the scanning so the layout
  can be corrected without touching the electrical code.
  """

  # One list per row, left to right. nil is a position with no switch under it.
  @layout [
    [
      nil,
      "Esc",
      "Square",
      "Triangle",
      "Cross",
      nil,
      nil,
      nil,
      "Circle",
      "Clover",
      "Diamond",
      "Bksp",
      nil
    ],
    ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
    ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"],
    ["Fn", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter"],
    ["LShift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Up", "RShift"],
    [
      "Ctrl",
      "SP",
      "Alt",
      "\\",
      "Space",
      "Space",
      "Space",
      "Space",
      nil,
      "AltGr",
      "Left",
      "Down",
      "Right"
    ]
  ]

  def label({row, col}) do
    @layout
    |> Enum.at(row)
    |> Enum.at(col)
  end
end
