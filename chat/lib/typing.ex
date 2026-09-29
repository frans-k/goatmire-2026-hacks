defmodule MyHack.Typing do
  @moduledoc """
  Turns key labels from `MyHack.Keymap` into the text they type, or nil for
  keys that type nothing (Enter, Tab, arrows, ...).
  """

  # US layout. Letters are handled separately, since their shifted form is just
  # the label itself.
  @shifted %{
    "`" => "~",
    "1" => "!",
    "2" => "@",
    "3" => "#",
    "4" => "$",
    "5" => "%",
    "6" => "^",
    "7" => "&",
    "8" => "*",
    "9" => "(",
    "0" => ")",
    "-" => "_",
    "=" => "+",
    "[" => "{",
    "]" => "}",
    "\\" => "|",
    ";" => ":",
    "'" => "\"",
    "," => "<",
    "." => ">",
    "/" => "?"
  }

  def char(<<c>>, true) when c in ?A..?Z, do: <<c>>
  def char(<<c>>, false) when c in ?A..?Z, do: <<c + 32>>
  def char("Space", _shifted), do: " "
  def char(label, true), do: Map.get(@shifted, label)
  # What is left with a single character is a digit or punctuation.
  def char(<<_>> = label, false), do: label
  def char(_label, false), do: nil
end
