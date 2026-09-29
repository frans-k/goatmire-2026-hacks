defmodule Raycaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :raycaster,
      version: "0.1.0",
      elixir: "~> 1.16",
      deps: deps(),
      # The frames the engine tests compare against, not a test file itself.
      test_ignore_filters: ["test/tour_frames.exs"],
      atomvm: [
        # Raycaster.Bench measures where the time goes instead of playing.
        start: Raycaster
      ]
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:atomvm, "~> 0.7.0-alpha.1", runtime: false},
      # Wraps the AtomGL display port in a gen_server that pushes a new display
      # list whenever a callback returns one. From git, because the published
      # Hex package ships no build config.
      {:avm_scene, github: "atomvm/avm_scene"},
      # MQTT 3.1.1 client in plain Erlang, for finding the other players.
      {:amqtt_client,
       github: "atomvm/amqtt",
       ref: "35fc07b37d1f76f25397c1d4355c91dd17149318",
       sparse: "amqtt_client"},
      {:exatomvm, github: "AtomVM/exatomvm", runtime: false},
      # Runs esptool in-process for the mix atomvm.esp32.* tasks.
      {:pythonx, "~> 0.4.0", runtime: false},
      # Downloads the firmware image for mix atomvm.esp32.install.
      {:req, "~> 0.5.0", runtime: false}
    ]
  end
end
