# Sends numbered messages to a badge, to check they append at the bottom of
# the screen and the oldest scroll off the top.
#
#     elixir scripts/send_messages.exs <badge id> [count]
#
# The badge id is printed on its screen and in the monitor, e.g. ee6f6c.

Mix.install([
  {:amqtt_client,
   git: "https://github.com/atomvm/amqtt.git", branch: "main", sparse: "amqtt_client"}
])

{id, count} =
  case System.argv() do
    [id] ->
      {id, 10}

    [id, count] ->
      {id, String.to_integer(count)}

    _ ->
      IO.puts(:stderr, "usage: elixir scripts/send_messages.exs <badge id> [count]") &&
        System.halt(1)
  end

# Same defaults as config/config.exs.
host = ~c"test.mosquitto.org"
topic = "goatmire/my_hack/#{id}/in/msg"

{:ok, client} =
  :amqtt_client.connect(%{
    host: host,
    port: 1883,
    client_id: "my_hack-script-#{:rand.uniform(100_000)}"
  })

receive do
  {:mqtt, ^client, :connack, _} -> :ok
after
  10_000 -> IO.puts(:stderr, "no answer from #{host}") && System.halt(1)
end

for n <- 1..count do
  :ok = :amqtt_client.publish(client, topic, "number #{n}", 0)
  IO.puts("#{topic} number #{n}")
  Process.sleep(300)
end

:amqtt_client.disconnect(client)
