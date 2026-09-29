import Config

config :my_hack, :wifi,
  ssid: "YOUR_WIFI",
  psk: "YOUR_PASSWORD"

# The host is handed to gen_tcp, and AtomVM resolves charlists, not binaries.
config :my_hack, :mqtt,
  host: ~c"test.mosquitto.org",
  port: 1883

# Everything the badge says or hears lives under <prefix>/<badge id>/.
# test.mosquitto.org is public, so pick something unlikely to collide.
config :my_hack, :topic_prefix, "goatmire/my_hack"

# Keep real credentials out of git: create config/config_local.exs with the
# same shape and it overrides what is above.
if File.exists?(Path.join(__DIR__, "config_local.exs")) do
  import_config("config_local.exs")
end
