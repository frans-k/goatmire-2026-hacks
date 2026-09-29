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

# Use a relay server (see relay/) instead of MQTT: RAYCASTER_RELAY=ws://host:4040,
# read while compiling. The relay puts badges in rooms of eight by itself and tells
# each one who is where once a second, which is far less for a badge to take in.
config :raycaster, :relay, System.get_env("RAYCASTER_RELAY")

# For measuring: RAYCASTER_AUTOPILOT=1 turns on the spot by itself, so every run
# casts the same views, and RAYCASTER_OFFLINE=1 leaves the network out whatever
# config_local.exs says. Read while compiling, like the rest.
config :raycaster, :autopilot, System.get_env("RAYCASTER_AUTOPILOT") == "1"

if System.get_env("RAYCASTER_OFFLINE") == "1" do
  config :raycaster, :wifi, ssid: nil, psk: nil
end
