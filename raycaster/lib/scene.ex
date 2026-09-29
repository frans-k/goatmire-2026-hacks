defmodule Raycaster.Scene do
  @moduledoc """
  A scene that draws whatever display list it is handed.

  The caller asks with a call, not a message: avm_scene answers only after the
  display has taken the list, so the game cannot run ahead of the screen and
  the time a call takes is the time the display takes.
  """

  def start_link(args, opts) do
    :avm_scene.start_link(__MODULE__, args, opts)
  end

  def init(args), do: {:ok, args}

  def handle_call({:frame, items}, _from, state) do
    {:reply, :ok, state, [{:push, items}]}
  end

  def handle_cast(_message, state), do: {:noreply, state}

  def handle_info(_message, state), do: {:noreply, state}
end
