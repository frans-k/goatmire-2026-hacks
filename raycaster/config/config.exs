import Config

# Multiplayer needs wifi. Leave the ssid nil to play alone: the game starts
# either way. Put real credentials in config/config_local.exs, which is not in
# git, with the same shape as this:
#
#     import Config
#     config :raycaster, :wifi, ssid: "my network", psk: "my password"
config :raycaster, :wifi, ssid: nil, psk: nil

# Everyone playing must use the same broker. test.mosquitto.org is public and
# open to anyone, so positions on it can be read or faked by anybody.
# The host is handed to gen_tcp, and AtomVM resolves charlists, not binaries.
config :raycaster, :mqtt,
  host: ~c"test.mosquitto.org",
  port: 1883

if File.exists?(Path.join(__DIR__, "config_local.exs")) do
  import_config("config_local.exs")
end
