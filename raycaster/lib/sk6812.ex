defmodule Raycaster.SK6812 do
  @moduledoc """
  Drives the badge's four SK6812MINI-E LEDs with the SPI peripheral used as a
  waveform generator. Adapted from `../chat/lib/sk6812.ex`.

  These LEDs read a self-clocked stream where each bit is a fixed-width pulse
  and the length of its high part carries the value. At 3.2 MHz one SPI bit
  lasts about 312 ns, so every LED bit is sent as four SPI bits: `0b1000` is a
  zero, `0b1100` is a one. Holding the line low afterwards latches the frame.

  `encode/1` builds a whole frame as a binary, so a frame that is shown over and
  over is built once and only written after that.
  """

  import Bitwise

  @data_pin 14
  @peripheral "spi3"
  @device :pixels
  @clock_speed_hz 3_200_000

  # The chain has no clock line, so SCLK is -1 and so is CS.
  def open do
    :spi.open(%{
      bus_config: %{peripheral: @peripheral, sclk: -1, mosi: @data_pin},
      device_config: %{
        @device => %{
          clock_speed_hz: @clock_speed_hz,
          mode: 0,
          cs: -1,
          address_len_bits: 0,
          command_len_bits: 0
        }
      }
    })
  end

  @doc "Writes a frame made by `encode/1`."
  def write(spi, frame), do: :spi.write(spi, @device, %{write_data: frame})

  @doc "Four `{r, g, b}` as a frame to write, with the latch after it."
  def encode(pixels), do: <<pixels(pixels)::binary, 0::size(320)>>

  defp pixels([]), do: <<>>
  defp pixels([pixel | rest]), do: <<pixel(pixel)::binary, pixels(rest)::binary>>

  # SK6812 and WS2812 both take green first.
  defp pixel({r, g, b}), do: <<byte(g)::binary, byte(r)::binary, byte(b)::binary>>

  defp byte(byte) do
    <<expand(byte >>> 6), expand(byte >>> 4), expand(byte >>> 2), expand(byte)>>
  end

  # A pair of LED bits as one SPI byte. Clauses rather than a tuple: AtomVM
  # copies a module literal every time it is used.
  defp expand(bits) do
    case bits &&& 3 do
      0 -> 0x88
      1 -> 0x8C
      2 -> 0xC8
      3 -> 0xCC
    end
  end
end
