defmodule Relay.Ghosts do
  @moduledoc """
  A few `Relay.Ghost`s, started when `GHOSTS` says how many (none by default).
  """

  use Supervisor

  def start_link(count), do: Supervisor.start_link(__MODULE__, count)

  @impl true
  def init(count) do
    children =
      for n <- 1..count//1, do: Supervisor.child_spec({Relay.Ghost, n}, id: {Relay.Ghost, n})

    Supervisor.init(children, strategy: :one_for_one)
  end
end
