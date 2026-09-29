import Config

# The port badges connect to, and how often every room is told who is where.
config :relay, port: 4040, tick_ms: 1_000

import_config "#{config_env()}.exs"
