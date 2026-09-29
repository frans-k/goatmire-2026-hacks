defmodule MyHack.Link do
  @moduledoc """
  The badge's connection to the outside world: one MQTT session, kept alive.

  Everything lives under a base topic, `<prefix>/<badge id>`:

    * `<base>/in/#` is subscribed to, and what arrives is handed to the owner
    * `<base>/out/<subtopic>` is where `publish/4` writes
    * `<base>/out/status` says `online` (retained) while connected, and the
      broker says `offline` on the badge's behalf when the link dies

  The owner, the process that called `start_link/1`, gets:

    * `{:link, :up}` once connected and subscribed
    * `{:link, :down}` when the session is lost; reconnecting is automatic
    * `{:message, subtopic, payload}` for each publish under `<base>/in/`
  """

  use GenServer

  @reconnect_ms 3_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, Keyword.put(opts, :owner, self()))
  end

  # Dropped, not queued, while the link is down: a badge that reconnects should
  # not replay stale news.
  def publish(link, subtopic, payload, opts \\ []) do
    GenServer.cast(link, {:publish, subtopic, payload, Keyword.get(opts, :retain, false)})
  end

  @impl true
  def init(opts) do
    # amqtt_client:connect/1 links to its caller and does the TCP connect inside
    # its own init, so an unreachable broker kills the caller too unless exits
    # are trapped and turned into messages.
    Process.flag(:trap_exit, true)

    base = Keyword.fetch!(opts, :base)

    state = %{
      owner: Keyword.fetch!(opts, :owner),
      host: Keyword.fetch!(opts, :host),
      port: Keyword.fetch!(opts, :port),
      client_id: Keyword.fetch!(opts, :client_id),
      in_prefix: base <> "/in/",
      out_prefix: base <> "/out/",
      client: nil,
      up: false
    }

    # Connecting is not done here so that first attempt and retries are the
    # same code path.
    send(self(), :connect)

    {:ok, state}
  end

  # The nonsense defaults that `use GenServer` would supply are built on
  # :erlang.phash2/2, which AtomVM does not have.
  @impl true
  def handle_call(_message, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_cast({:publish, subtopic, payload, retain}, %{up: true} = state) do
    :amqtt_client.publish(state.client, state.out_prefix <> subtopic, payload, 0, %{
      retain: retain
    })

    {:noreply, state}
  end

  def handle_cast({:publish, _subtopic, _payload, _retain}, state), do: {:noreply, state}

  # connect/1 returns as soon as the CONNECT packet is on its way. The broker
  # accepting it arrives later as :connack, to whoever called connect/1, which
  # is this process.
  @impl true
  def handle_info(:connect, state) do
    result =
      :amqtt_client.connect(%{
        host: state.host,
        port: state.port,
        client_id: state.client_id,
        will_topic: state.out_prefix <> "status",
        will_message: "offline",
        will_retain: true
      })

    case result do
      {:ok, client} ->
        {:noreply, %{state | client: client}}

      {:error, reason} ->
        IO.puts("MQTT connect failed: #{inspect(reason)}")
        {:noreply, lost(state)}
    end
  end

  def handle_info({:mqtt, client, :connack, _info}, %{client: client} = state) do
    {:ok, _granted} = :amqtt_client.subscribe(client, [{state.in_prefix <> "#", 0}])
    :amqtt_client.publish(client, state.out_prefix <> "status", "online", 0, %{retain: true})

    IO.puts("MQTT up, listening on #{state.in_prefix}#")
    send(state.owner, {:link, :up})

    {:noreply, %{state | up: true}}
  end

  def handle_info(
        {:mqtt, client, :publish, %{topic: topic, message: payload}},
        %{client: client} = state
      ) do
    case subtopic(topic, state.in_prefix) do
      {:ok, sub} -> send(state.owner, {:message, sub, payload})
      :error -> :ok
    end

    {:noreply, state}
  end

  # The broker hanging up and a transport error both end the session.
  def handle_info({:mqtt, client, :disconnected, _info}, %{client: client} = state) do
    IO.puts("MQTT disconnected")
    {:noreply, lost(state)}
  end

  def handle_info({:mqtt, client, :error, info}, %{client: client} = state) do
    IO.puts("MQTT error: #{inspect(info)}")
    {:noreply, lost(state)}
  end

  # The client process died. Usually a :disconnected or :error has already said
  # so and the client is gone from the state; if not, this is how it is noticed.
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

  defp lost(state) do
    if state.up, do: send(state.owner, {:link, :down})
    Process.send_after(self(), :connect, @reconnect_ms)

    %{state | client: nil, up: false}
  end

  defp subtopic(topic, prefix) do
    size = byte_size(prefix)

    case topic do
      <<^prefix::binary-size(size), rest::binary>> -> {:ok, rest}
      _ -> :error
    end
  end
end
