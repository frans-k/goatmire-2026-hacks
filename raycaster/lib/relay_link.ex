defmodule Raycaster.RelayLink do
  @moduledoc """
  The websocket to the relay server (see `relay/`), kept alive.

  The connection is the ESP-IDF websocket component's: it does the TCP, the TLS
  and the framing on a task of its own. `:connected` arrives on every connection,
  and the room has to be joined each time. The driver says it reconnects by itself,
  but after the server closed the connection (a relay restarted, say) it said
  `closed :normal` twice and never tried again, so on a close this closes it too and
  opens a new one a few seconds later. The owner, the game, is sent:

    * `{:link, :up}` once the server has put this badge in a room, and `{:link, :down}`
      when the connection is lost
    * `{:players, [{slot, x, y}], goat}` once a tick, everyone else in the room and
      the goat, `{x, y, hunting}` or nil
    * `:caught` when the goat has caught this badge

  `publish/3` says where this badge stands, and `respawn/1` that it is back after
  being caught; both are dropped while not in a room.
  """

  use GenServer

  alias Raycaster.RelayWire

  @compile {:no_warn_undefined, :websocket_client}

  @retry_ms 3_000
  @beat_ms 25_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Tells the server where this badge stands, in the map's fixed point."
  def publish(link, x, y), do: GenServer.cast(link, {:publish, x, y})

  @doc "Back in the game after being caught."
  def respawn(link), do: GenServer.cast(link, :respawn)

  @impl true
  def init(opts) do
    # Whatever goes wrong in here must not take the game with it, but it should be said.
    Process.flag(:trap_exit, true)

    state = %{
      owner: Keyword.fetch!(opts, :owner),
      url:
        RelayWire.url(
          Keyword.fetch!(opts, :base),
          Keyword.fetch!(opts, :chip),
          Keyword.get(opts, :token)
        ),
      port: nil,
      # How many times the room has been joined: each join is its own ref.
      joins: 0,
      slot: nil,
      ref: 0
    }

    send(self(), :open)
    Process.send_after(self(), :beat, @beat_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(_message, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_cast({:publish, x, y}, %{slot: slot, port: port} = state) when slot != nil do
    state = %{state | ref: state.ref + 1}
    send_text(port, RelayWire.pos(join_ref(state), Integer.to_string(state.ref), x, y))

    {:noreply, state}
  end

  def handle_cast(:respawn, %{slot: slot, port: port} = state) when slot != nil do
    state = %{state | ref: state.ref + 1}
    send_text(port, RelayWire.respawn(join_ref(state), Integer.to_string(state.ref)))

    {:noreply, state}
  end

  def handle_cast(_message, state), do: {:noreply, state}

  @impl true
  def handle_info(:open, state) do
    opts = %{
      url: state.url,
      owner: self(),
      verify: verify(state.url),
      network_timeout_ms: 30_000
    }

    case :websocket_client.open(opts) do
      {:ok, port} ->
        {:noreply, %{state | port: port}}

      {:error, reason} ->
        IO.puts("Relay: could not open #{state.url}: #{inspect(reason)}")
        Process.send_after(self(), :open, @retry_ms)
        {:noreply, state}
    end
  end

  # Not in a room yet: say hello. Every reconnection is a new join. The port in
  # these messages is not matched, and is not the one to send on: the driver's
  # port term is not the one open/1 returned, and a pinned match drops every
  # message without a word.
  def handle_info({:websocket, _port, :connected}, state) do
    state = %{state | joins: state.joins + 1, slot: nil}
    send_text(state.port, RelayWire.join(join_ref(state)))

    {:noreply, state}
  end

  def handle_info({:websocket, _port, {:text, text}}, state) do
    {:noreply, heard(RelayWire.decode(text, state.slot), state)}
  end

  def handle_info({:websocket, _port, {:closed, reason}}, state) do
    IO.puts("Relay: closed #{inspect(reason)}")
    {:noreply, state |> down() |> reopen()}
  end

  def handle_info({:websocket, _port, {:error, reason}}, state) do
    IO.puts("Relay: error #{inspect(reason)}")
    {:noreply, down(state)}
  end

  # Phoenix drops a connection that goes quiet.
  def handle_info(:beat, state) do
    if state.slot != nil, do: send_text(state.port, RelayWire.heartbeat())

    Process.send_after(self(), :beat, @beat_ms)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp heard({:joined, room, slot, max}, state) do
    IO.puts("Relay: room #{room}, slot #{slot} of #{max}")
    send(state.owner, {:link, :up})

    %{state | slot: slot}
  end

  defp heard({:players, players, goat}, state) do
    send(state.owner, {:players, players, goat})
    state
  end

  defp heard(:caught, state) do
    send(state.owner, :caught)
    state
  end

  defp heard(:ignore, state), do: state

  # Gives up on this connection and opens another in a while. A close can be said
  # more than once, and only the first one counts: after it there is no port until
  # the new one opens.
  defp reopen(%{port: nil} = state), do: state

  defp reopen(state) do
    close(state.port)
    Process.send_after(self(), :open, @retry_ms)
    %{state | port: nil}
  end

  defp close(port) do
    :websocket_client.close(port)
  catch
    _kind, _reason -> :ok
  end

  defp down(state) do
    if state.slot != nil, do: send(state.owner, {:link, :down})
    %{state | slot: nil}
  end

  defp join_ref(state), do: Integer.to_string(state.joins)

  # While the connection is down the driver refuses, with `{:error, :not_connected}`
  # by its documentation but a bare `:not_connected` on the badge, which crashed
  # the link when only the first was matched. Whatever it says, a refusal is only
  # said: what was sent is lost, and the next position replaces it anyway.
  defp send_text(nil, _text), do: :ok

  defp send_text(port, text) do
    case :websocket_client.send_text(port, text) do
      :ok -> :ok
      refused -> IO.puts("Relay: refused #{inspect(refused)}")
    end
  end

  # Without an explicit verify the driver disables verification and warns.
  defp verify("ws://" <> _), do: :none
  defp verify(_), do: :crt_bundle
end
