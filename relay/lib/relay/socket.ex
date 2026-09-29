defmodule Relay.Socket do
  @moduledoc """
  One badge's websocket, speaking the part of Phoenix channels (serializer 2.0.0)
  that a badge's chat client already does, so the same code on the badge talks to
  this:

      [join_ref, ref, topic, event, payload]

    * `phx_join` on `raycaster:lobby` is answered with the room, the slot and the
      most a room holds: `{"room": 3, "slot": 2, "max": 8}`
    * `pos`, `{"x": 300, "y": 512}`, is where the badge stands; no answer
    * `heartbeat` on `phoenix` and `phx_leave` are answered as Phoenix does
    * the hub pushes `snap`, `{"p": [[slot, x, y], ...]}`, once a tick

  Anything else is ignored: this is open to anyone, and only ever answers what it
  understands.
  """

  @behaviour WebSock

  alias Relay.Hub

  @impl true
  def init(_opts), do: {:ok, %{joined: false}}

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case JSON.decode(text) do
      {:ok, [join_ref, ref, topic, event, payload]} ->
        handle_frame(join_ref, ref, topic, event, payload, state)

      _garbage ->
        {:ok, state}
    end
  end

  def handle_in(_binary_or_other, state), do: {:ok, state}

  defp handle_frame(join_ref, ref, "raycaster:lobby" = topic, "phx_join", _payload, state) do
    case Hub.join(self()) do
      {room, slot, max} ->
        reply = ok_reply(join_ref, ref, topic, %{"room" => room, "slot" => slot, "max" => max})
        {:push, {:text, reply}, %{state | joined: true}}

      {:error, :full} ->
        reply = error_reply(join_ref, ref, topic, "full")
        {:push, {:text, reply}, state}
    end
  end

  defp handle_frame(join_ref, ref, topic, "phx_join", _payload, state) do
    {:push, {:text, error_reply(join_ref, ref, topic, "unknown topic")}, state}
  end

  defp handle_frame(
         _join_ref,
         _ref,
         "raycaster:lobby",
         "pos",
         %{"x" => x, "y" => y},
         %{joined: true} = state
       ) do
    Hub.move(self(), x, y)
    {:ok, state}
  end

  defp handle_frame(nil, ref, "phoenix", "heartbeat", _payload, state) do
    {:push, {:text, ok_reply(nil, ref, "phoenix", %{})}, state}
  end

  defp handle_frame(join_ref, ref, "raycaster:lobby" = topic, "phx_leave", _payload, state) do
    Hub.leave(self())
    {:push, {:text, ok_reply(join_ref, ref, topic, %{})}, %{state | joined: false}}
  end

  defp handle_frame(_join_ref, _ref, _topic, _event, _payload, state), do: {:ok, state}

  @impl true
  def handle_info({:snap, frame}, %{joined: true} = state), do: {:push, {:text, frame}, state}
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state) do
    Hub.leave(self())
    :ok
  end

  defp error_reply(join_ref, ref, topic, reason) do
    JSON.encode!([
      join_ref,
      ref,
      topic,
      "phx_reply",
      %{"status" => "error", "response" => %{"reason" => reason}}
    ])
  end

  defp ok_reply(join_ref, ref, topic, response) do
    JSON.encode!([join_ref, ref, topic, "phx_reply", %{"status" => "ok", "response" => response}])
  end
end
