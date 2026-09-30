import Config

# Multiplayer needs wifi and a relay (below). Leave the ssid nil to play alone: the
# game starts either way. Put real credentials in config/config_local.exs, which is not in
# git, with the same shape as this:
#
#     import Config
#     config :raycaster, :wifi, ssid: "my network", psk: "my password"
config :raycaster, :wifi, ssid: nil, psk: nil

if File.exists?(Path.join(__DIR__, "config_local.exs")) do
  import_config("config_local.exs")
end

# The relay server (see relay/) badges play through: RAYCASTER_RELAY=wss://host or
# ws://host:4040, read while compiling. It puts badges in rooms of eight by itself
# and tells each one who is where once a second. Without it the game is solo.
config :raycaster, :relay, System.get_env("RAYCASTER_RELAY")

# The token the relay asks for, if it does (RELAY_TOKEN on the server): letters,
# digits and -_.~ only. It ends up in the badge's firmware, so it keeps casual
# visitors out and nobody who reads the firmware.
config :raycaster, :relay_token, System.get_env("RAYCASTER_RELAY_TOKEN")

# For measuring: RAYCASTER_AUTOPILOT=1 turns on the spot by itself, so every run
# casts the same views, and RAYCASTER_OFFLINE=1 leaves the network out whatever
# config_local.exs says. Read while compiling, like the rest.
config :raycaster, :autopilot, System.get_env("RAYCASTER_AUTOPILOT") == "1"

# RAYCASTER_STATS=1 draws the frames per second and where the time went in the top
# corner, as the monitor prints them. Without it only the line saying who is
# playing is on screen.
config :raycaster, :stats, System.get_env("RAYCASTER_STATS") == "1"

# RAYCASTER_GOAT=1 stands the evil goat in the corridor ahead of where you start,
# hunting, to see it on the badge before the relay can send one.
config :raycaster, :goat, System.get_env("RAYCASTER_GOAT") == "1"

if System.get_env("RAYCASTER_OFFLINE") == "1" do
  config :raycaster, :wifi, ssid: nil, psk: nil
end
