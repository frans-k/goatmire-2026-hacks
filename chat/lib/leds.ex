defmodule MyHack.Leds do
  @moduledoc """
  The badge's four LEDs, driven from text so anything can set them over MQTT.

  A spec is `off`, one colour for all four, or four colours left to right,
  each written `#rrggbb` and separated by spaces:

      #ff0000
      #ff0000 #00ff00 #0000ff #000000
  """

  alias MyHack.SK6812

  @count 4

  # Out of 255. Four LEDs at full brightness are unpleasant to look at and draw
  # a lot more current, so whatever is asked for is scaled down to this.
  @brightness 64

  defdelegate open(), to: SK6812

  # Returns :ok, or :error when the spec makes no sense (nothing is written).
  def show(spi, spec) do
    case parse(spec) do
      {:ok, pixels} -> SK6812.write(spi, dim(pixels))
      :error -> :error
    end
  end

  def parse("off"), do: parse("#000000")

  def parse(spec) do
    case scan(spec, []) do
      {:ok, [colour]} -> {:ok, List.duplicate(colour, @count)}
      {:ok, colours} when length(colours) == @count -> {:ok, colours}
      _ -> :error
    end
  end

  defp scan(<<>>, acc), do: {:ok, :lists.reverse(acc)}
  defp scan(<<" ", rest::binary>>, acc), do: scan(rest, acc)

  defp scan(<<"#", hex::binary-size(6), rest::binary>>, acc) do
    case colour(hex) do
      {:ok, colour} -> scan(rest, [colour | acc])
      :error -> :error
    end
  end

  defp scan(_spec, _acc), do: :error

  defp colour(hex) do
    number = :erlang.binary_to_integer(hex, 16)

    if number >= 0 do
      {:ok, {div(number, 65_536), rem(div(number, 256), 256), rem(number, 256)}}
    else
      :error
    end
  catch
    :error, _ -> :error
  end

  defp dim(pixels) do
    Enum.map(pixels, fn {r, g, b} ->
      {div(r * @brightness, 255), div(g * @brightness, 255), div(b * @brightness, 255)}
    end)
  end
end
