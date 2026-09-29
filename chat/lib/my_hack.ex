defmodule MyHack do
  @moduledoc """
  Entry point: screen first, so there is something to look at while the rest
  comes up, then Wi-Fi, then the app.
  """

  alias MyHack.{App, Badge, Screen, Wifi}

  # Everything worth changing lives in config/config.exs. compile_env! reads it
  # while compiling on the laptop, so the badge never sees Application at all.
  @ssid Application.compile_env!(:my_hack, [:wifi, :ssid])
  @psk Application.compile_env!(:my_hack, [:wifi, :psk])
  @broker Application.compile_env!(:my_hack, [:mqtt, :host])
  @broker_port Application.compile_env!(:my_hack, [:mqtt, :port])
  @topic_prefix Application.compile_env!(:my_hack, :topic_prefix)

  def start do
    id = Badge.id()
    {:ok, screen} = Screen.start()

    Screen.update(screen, %{title: "badge " <> id, wifi: :connecting})
    IO.puts("Connecting to #{@ssid}...")

    case Wifi.connect(@ssid, @psk) do
      {:ok, address} ->
        IO.puts("Connected, IP #{address}")
        Screen.update(screen, %{wifi: {:up, address}})

      {:error, reason} ->
        # Nothing else can work without a network, so say why and stop.
        IO.puts("WiFi failed: #{inspect(reason)}")
        Screen.update(screen, %{wifi: :down, lines: ["wifi: #{inspect(reason)}"]})
        exit({:wifi, reason})
    end

    base = "#{@topic_prefix}/#{id}"

    {:ok, _app} =
      App.start_link(
        screen: screen,
        title: base,
        link: [host: @broker, port: @broker_port, client_id: "my_hack-" <> id, base: base]
      )

    park()
  end

  # The processes doing the work are linked to this one, so it has to stay.
  defp park do
    receive do
      _message -> park()
    end
  end
end
