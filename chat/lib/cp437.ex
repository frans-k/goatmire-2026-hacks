defmodule MyHack.Cp437 do
  @moduledoc """
  UTF-8 to the badge font's encoding.

  AtomGL draws one glyph per byte from the Linux VGA font, laid out as CP437.
  UTF-8 `ö` is two bytes and would draw two wrong glyphs; CP437 has it as the
  single byte 0x94. Accented letters the font lacks (Ł, ń, č, Á, ...) are drawn
  as their plain letter, so names stay readable; anything else becomes `?`.
  """

  # 0x80..0xAF in CP437 order.
  @high ~c"ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»"

  # Letters CP437 has no glyph for, and what to draw instead.
  @folded [
    {"ÀÁÂÃĀĂĄ", "A"},
    {"àáâãāăą", "a"},
    {"ÇĆĈČ", "C"},
    {"çćĉč", "c"},
    {"ĎĐÐ", "D"},
    {"ďđð", "d"},
    {"ÈÊËĒĖĘĚ", "E"},
    {"èêëēėęě", "e"},
    {"ĞĜ", "G"},
    {"ğĝ", "g"},
    {"ÌÍÎÏĪĮİ", "I"},
    {"ìíîïīįı", "i"},
    {"Ł", "L"},
    {"ł", "l"},
    {"ÑŃŇ", "N"},
    {"ñńň", "n"},
    {"ÒÓÔÕŌŐØ", "O"},
    {"òóôõōőø", "o"},
    {"ŘŔ", "R"},
    {"řŕ", "r"},
    {"ŚŠŞȘ", "S"},
    {"śšşș", "s"},
    {"ŤŢȚ", "T"},
    {"ťţț", "t"},
    {"ÙÚÛŪŮŰŲ", "U"},
    {"ùúûūůűų", "u"},
    {"ÝŸ", "Y"},
    {"ýÿ", "y"},
    {"ŹŻŽ", "Z"},
    {"źżž", "z"},
    {"Þ", "Th"},
    {"þ", "th"}
  ]

  # CP437 already has some of these (ü, é, ö, ...), and those win below.
  @fold for(
          {letters, plain} <- @folded,
          char <- String.to_charlist(letters),
          into: %{},
          do: {char, plain}
        )

  @table Map.merge(
           @fold,
           Map.merge(
             for({char, byte} <- Enum.zip(@high, 0x80..0xAF), into: %{}, do: {char, <<byte>>}),
             %{
               ?ß => <<0xE1>>,
               ?µ => <<0xE6>>,
               ?± => <<0xF1>>,
               ?÷ => <<0xF6>>,
               ?° => <<0xF8>>,
               ?· => <<0xFA>>,
               ?² => <<0xFD>>,
               # Typography that has a plain ASCII stand-in.
               0x2018 => "'",
               0x2019 => "'",
               0x201C => "\"",
               0x201D => "\"",
               0x2013 => "-",
               0x2014 => "-",
               0x2026 => "..."
             }
           )
         )

  def from_utf8(text), do: convert(text, [])

  defp convert(<<>>, acc), do: :erlang.list_to_binary(:lists.reverse(acc))

  defp convert(<<char, rest::binary>>, acc) when char < 0x80, do: convert(rest, [char | acc])

  defp convert(<<char::utf8, rest::binary>>, acc) do
    convert(rest, [Map.get(@table, char, "?") | acc])
  end

  # Not valid UTF-8 at all, so one byte cannot be trusted either.
  defp convert(<<_, rest::binary>>, acc), do: convert(rest, ["?" | acc])
end
