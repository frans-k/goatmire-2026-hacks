defmodule Relay.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:relay, :port, 4040)

    children = [
      Relay.Stats,
      Relay.Hub,
      {Bandit, plug: Relay.Router, port: port, ip: {0, 0, 0, 0}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Relay.Supervisor)
  end
end
