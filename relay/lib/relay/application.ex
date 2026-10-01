defmodule Relay.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:relay, :port, 4040)

    ghosts = Application.get_env(:relay, :ghosts, 0)

    children =
      [Relay.Stats, Relay.Hub] ++
        if(ghosts > 0, do: [{Relay.Ghosts, ghosts}], else: []) ++
        [{Bandit, plug: Relay.Router, port: port, ip: {0, 0, 0, 0}}]

    Supervisor.start_link(children, strategy: :one_for_one, name: Relay.Supervisor)
  end
end
