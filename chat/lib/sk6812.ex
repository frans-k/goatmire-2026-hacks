defmodule MyHack.SK6812 do
  @moduledoc """
  Drives the badge's four SK6812MINI-E LEDs with the SPI peripheral used as a
  waveform generator.

  These LEDs read a self-clocked stream where each bit is a fixed-width pulse
  and the length of its high part carries the value. At 3.2 MHz one SPI bit
  lasts about 312 ns, so every LED bit is sent as four SPI bits: `0b1000` is a
  zero, `0b1100` is a one. Holding the line low afterwards latches the frame.

  Bit banging this from Elixir would not hold the timing. The SPI peripheral
  clocks it out in hardware instead.
  """

  import Bitwise

  @data_pin 14
  @peripheral "spi3"
  @device :pixels
  @clock_speed_hz 3_200_000

  # Indexed by a pair of LED bits, so one colour byte becomes four SPI bytes.
  @nibble_pairs {0x88, 0x8C, 0xC8, 0xCC}

  # Idle bytes, long enough to hold the line low past the reset threshold.
  @latch :binary.copy(<<0>>, 40)

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

  def write(spi, pixels) do
    frame =
      pixels
      |> Enum.map(&encode_pixel/1)
      |> Enum.reduce(<<>>, fn pixel, acc -> acc <> pixel end)

    :ok = :spi.write(spi, @device, %{write_data: frame <> @latch})
  end

  # SK6812 and WS2812 both take green first.
  defp encode_pixel({r, g, b}), do: encode_byte(g) <> encode_byte(r) <> encode_byte(b)

  defp encode_byte(byte) do
    <<expand(byte >>> 6), expand(byte >>> 4), expand(byte >>> 2), expand(byte)>>
  end

  defp expand(bits), do: elem(@nibble_pairs, bits &&& 0x03)
end
