defmodule Raycaster.Screen do
  @moduledoc """
  The badge's display: hardware setup, and a `Raycaster.Scene` process that
  draws to it.
  """

  # Panel: ST7789 over SPI, mounted landscape, so 320x240 with rotation 3.
  @width 320
  @height 240

  @spi_peripheral "spi2"
  @spi_sclk 5
  @spi_mosi 8
  @spi_miso 9

  @display_cs 7
  @display_dc 4
  @display_reset 6
  @display_backlight 3

  def width, do: @width
  def height, do: @height

  def start do
    spi = open_spi()
    display = :erlang.open_port({:spawn, "display"}, display_opts(spi))

    Raycaster.Scene.start_link([width: @width, height: @height], display_server: {:port, display})
  end

  # AtomGL adds its own SPI device, so device_config stays empty here.
  defp open_spi do
    :spi.open(%{
      bus_config: %{
        peripheral: @spi_peripheral,
        sclk: @spi_sclk,
        mosi: @spi_mosi,
        miso: @spi_miso
      },
      device_config: %{}
    })
  end

  defp display_opts(spi) do
    [
      compatible: "sitronix,st7789",
      init_seq_type: "alt_gamma_2",
      enable_tft_invon: true,
      width: @width,
      height: @height,
      rotation: 3,
      reset: @display_reset,
      dc: @display_dc,
      cs: @display_cs,
      backlight: @display_backlight,
      backlight_active: :low,
      backlight_enabled: true,
      # The driver defaults to 40 MHz, which takes about 31 ms just to move a
      # frame. The badge firmware runs the panel at 80 MHz.
      clock_speed_hz: 80_000_000,
      spi_host: spi
    ]
  end
end
