defmodule Relay.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = System.get_env("PORT") |> port(Application.get_env(:relay, :port, 4040))

    children = [
      Relay.Hub,
      {Bandit, plug: Relay.Router, port: port, ip: {0, 0, 0, 0}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Relay.Supervisor)
  end

  defp port(nil, default), do: default

  defp port(text, default) do
    case Integer.parse(text) do
      {port, ""} when port > 0 and port < 65_536 -> port
      _other -> default
    end
  end
end
