defmodule MyHack.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_hack,
      version: "0.1.0",
      elixir: "~> 1.16",
      deps: deps(),
      atomvm: [
        start: MyHack
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
      # MQTT 3.1.1 client in plain Erlang.
      {:amqtt_client,
       git: "https://github.com/atomvm/amqtt.git", branch: "main", sparse: "amqtt_client"},
      {:exatomvm, github: "AtomVM/exatomvm", runtime: false},
      {:pythonx, "~> 0.4.0", runtime: false},
      {:req, "~> 0.5.0", runtime: false}
    ]
  end
end
