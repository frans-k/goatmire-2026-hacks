# Logs every message under the topic prefix to a file, so it can be tailed:
#
#     elixir scripts/log_messages.exs [--host HOST] [--port PORT] [--file PATH]
#     tail -f log/my_hack.log
#
# Broker and prefix come from config/config.exs (and config_local.exs), the
# same place the badge gets them, so the two cannot drift apart. It covers all
# badges: <prefix>/<id>/in/..., out/..., and the retained out/status.

Mix.install([
  {:amqtt_client,
   git: "https://github.com/atomvm/amqtt.git", branch: "main", sparse: "amqtt_client"}
])

defmodule Logger.Script do
  @reconnect_ms 3_000

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [host: :string, port: :integer, file: :string])

    config = Config.Reader.read!(Path.expand("../config/config.exs", __DIR__))
    mqtt = get_in(config, [:my_hack, :mqtt])
    prefix = get_in(config, [:my_hack, :topic_prefix])

    host = if opts[:host], do: String.to_charlist(opts[:host]), else: mqtt[:host]
    port = opts[:port] || mqtt[:port]
    path = Path.expand(opts[:file] || "../log/my_hack.log", __DIR__)

    File.mkdir_p!(Path.dirname(path))
    file = File.open!(path, [:append, :binary])

    IO.puts("#{prefix}/# on #{host}:#{port} -> #{path}")
    IO.puts("tail -f #{Path.relative_to_cwd(path)}")

    # amqtt_client links to its caller, so an unreachable broker would kill this
    # script instead of being retried.
    Process.flag(:trap_exit, true)
    loop(%{host: host, port: port, topic: prefix <> "/#", file: file})
  end

  defp loop(cfg) do
    write(cfg, "--", "connecting to #{cfg.host}:#{cfg.port}")
    session(cfg)
    Process.sleep(@reconnect_ms)
    loop(cfg)
  end

  # Returns when the session is lost, for whatever reason.
  defp session(cfg) do
    flush()

    client_id = "my_hack-logger-#{:rand.uniform(1_000_000)}"

    case :amqtt_client.connect(%{host: cfg.host, port: cfg.port, client_id: client_id}) do
      {:ok, client} -> wait_connack(cfg, client)
      {:error, reason} -> write(cfg, "--", "connect failed: #{inspect(reason)}")
    end
  end

  defp wait_connack(cfg, client) do
    receive do
      {:mqtt, ^client, :connack, _} ->
        {:ok, _} = :amqtt_client.subscribe(client, [{cfg.topic, 0}])
        write(cfg, "--", "subscribed to #{cfg.topic}")
        receive_loop(cfg, client)

      {:mqtt, ^client, _, _} ->
        write(cfg, "--", "refused")

      {:EXIT, ^client, reason} ->
        write(cfg, "--", "connect failed: #{inspect(reason)}")
    after
      15_000 -> write(cfg, "--", "no answer from broker")
    end
  end

  defp receive_loop(cfg, client) do
    receive do
      {:mqtt, ^client, :publish, %{topic: topic, message: payload}} ->
        write(cfg, topic, payload)
        receive_loop(cfg, client)

      {:mqtt, ^client, :disconnected, _} ->
        write(cfg, "--", "disconnected")

      {:mqtt, ^client, :error, info} ->
        write(cfg, "--", "error: #{inspect(info)}")

      {:EXIT, ^client, reason} ->
        write(cfg, "--", "client exited: #{inspect(reason)}")
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  # One line per message: newlines in a payload would break tailing.
  defp write(cfg, topic, payload) do
    stamp = DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
    text = payload |> String.replace("\r", "") |> String.replace("\n", "\\n")

    IO.binwrite(cfg.file, "#{stamp} #{topic} #{text}\n")
  end
end

Logger.Script.main(System.argv())
