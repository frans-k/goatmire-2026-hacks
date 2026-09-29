defmodule MyHack.Screen do
  @moduledoc """
  The badge's display: hardware setup, and one process that draws.

  `start/0` returns the scene process; `update/2` tells it what to show.
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

  def start do
    spi = open_spi()
    display = :erlang.open_port({:spawn, "display"}, display_opts(spi))

    MyHack.Scene.start_link([width: @width, height: @height], display_server: {:port, display})
  end

  # A plain message, so anything on the badge can update the screen without
  # going through a call.
  def update(screen, changes) when is_map(changes), do: send(screen, {:update, changes})

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
      spi_host: spi
    ]
  end
end
