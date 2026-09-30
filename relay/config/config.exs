import Config

# The port badges connect to, how often every room is told who is where, and how
# often the goats move.
config :relay, port: 4040, tick_ms: 1_000, goat_ms: 100

import_config "#{config_env()}.exs"
