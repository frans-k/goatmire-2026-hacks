defmodule Raycaster.Link do
  @moduledoc """
  One MQTT session, kept alive, for finding the other players.

  It listens to every badge's position (`Raycaster.Wire.filter/0`) and the owner,
  the game, is sent:

    * `{:link, :up}` once connected and subscribed, `{:link, :down}` when lost
    * `{:peer, id, pose}` for another badge's position
    * `{:gone, id}` for one that said goodbye, or that the broker says died

  `publish/2` tells the others where this badge is, and is dropped, not queued,
  while the link is down: a badge that reconnects should not replay old news. When
  the session is lost it reconnects on its own. The badge's own position comes back
  to it, since it hears every badge, and is dropped here, as is anything that does
  not decode: the broker is open to anyone.
  """

  use GenServer

  alias Raycaster.Wire

  @reconnect_ms 3_000
  @keep_alive_s 30

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Tells the others where this badge is."
  def publish(link, payload), do: GenServer.cast(link, {:publish, payload})

  @impl true
  def init(opts) do
    # amqtt_client:connect/1 links to its caller and connects inside its own
    # init, so an unreachable broker would kill this process too unless exits are
    # turned into messages.
    Process.flag(:trap_exit, true)

    state = %{
      owner: Keyword.fetch!(opts, :owner),
      host: Keyword.fetch!(opts, :host),
      port: Keyword.fetch!(opts, :port),
      id: Keyword.fetch!(opts, :id),
      client: nil,
      up: false
    }

    send(self(), :connect)

    {:ok, state}
  end

  # The defaults `use GenServer` would supply are built on :erlang.phash2/2,
  # which AtomVM does not have.
  @impl true
  def handle_call(_message, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_cast({:publish, payload}, %{up: true} = state) do
    :amqtt_client.publish(state.client, Wire.topic(state.id), payload, 0)
    {:noreply, state}
  end

  def handle_cast({:publish, _payload}, state), do: {:noreply, state}
  def handle_cast(_message, state), do: {:noreply, state}

  @impl true
  def handle_info(:connect, state) do
    result =
      :amqtt_client.connect(%{
        host: state.host,
        port: state.port,
        client_id: ~c"avm-rc-" ++ :erlang.binary_to_list(state.id),
        keep_alive_seconds: @keep_alive_s,
        # An empty payload on our own topic, sent by the broker if this badge
        # dies, is how the others learn it has gone.
        will_topic: Wire.topic(state.id),
        will_message: <<>>,
        will_retain: false
      })

    case result do
      {:ok, client} ->
        {:noreply, %{state | client: client}}

      {:error, reason} ->
        IO.puts("MQTT connect failed: #{inspect(reason)}")
        {:noreply, lost(state)}
    end
  end

  # connect/1 returns as soon as the CONNECT packet is on its way; the broker
  # accepting it arrives later, to whoever called connect/1, which is this process.
  def handle_info({:mqtt, client, :connack, _info}, %{client: client} = state) do
    {:ok, _granted} = :amqtt_client.subscribe(client, [{Wire.filter(), 0}])

    IO.puts("MQTT up, listening on #{Wire.filter()}")
    send(state.owner, {:link, :up})

    {:noreply, %{state | up: true}}
  end

  def handle_info(
        {:mqtt, client, :publish, %{topic: topic, message: payload}},
        %{client: client} = state
      ) do
    heard(state, topic, payload)
    {:noreply, state}
  end

  def handle_info({:mqtt, client, :disconnected, _info}, %{client: client} = state) do
    IO.puts("MQTT disconnected")
    {:noreply, lost(state)}
  end

  def handle_info({:mqtt, client, :error, info}, %{client: client} = state) do
    IO.puts("MQTT error: #{inspect(info)}")
    {:noreply, lost(state)}
  end

  def handle_info({:EXIT, client, reason}, %{client: client} = state) do
    IO.puts("MQTT client exited: #{inspect(reason)}")
    {:noreply, lost(state)}
  end

  # Our owner is gone, so there is nobody left to serve.
  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    {:stop, reason, state}
  end

  # Anything else is from a session that has already been given up on.
  def handle_info(_message, state), do: {:noreply, state}

  defp heard(%{id: own, owner: owner}, topic, payload) do
    case Wire.id(topic) do
      {:ok, ^own} -> :ok
      {:ok, id} -> tell(owner, id, Wire.decode(payload))
      :error -> :ok
    end
  end

  defp tell(owner, id, {:ok, pose}), do: send(owner, {:peer, id, pose})
  defp tell(owner, id, :gone), do: send(owner, {:gone, id})
  defp tell(_owner, _id, :error), do: :ok

  defp lost(state) do
    if state.up, do: send(state.owner, {:link, :down})
    Process.send_after(self(), :connect, @reconnect_ms)

    %{state | client: nil, up: false}
  end
end
