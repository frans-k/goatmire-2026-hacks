import Config

# Read when the server starts, also from a release. Only what is set is changed.
#
#   PORT          the port badges connect to (4040)
#   RELAY_TOKEN   a shared token a badge must send as ?token=..., or anyone may join.
#                 It is in every badge's firmware, so it keeps casual visitors out,
#                 not someone who reads the firmware
#   RELAY_MAX     the most connections at once, in all rooms (300)
#   STATS_PATH    the file the player counts are kept in, on a volume so that a restart
#                 keeps them (none: counted in memory only)
#   STATS_UTC_OFFSET_HOURS  where a day starts, from UTC (2)
#   GHOSTS        how many players that are not badges wander the map, for someone trying the
#                 game on their own to find (0). They are left out of the counts
if port = System.get_env("PORT"), do: config(:relay, port: String.to_integer(port))
if token = System.get_env("RELAY_TOKEN"), do: config(:relay, token: token)
if path = System.get_env("STATS_PATH"), do: config(:relay, stats_path: path)

if hours = System.get_env("STATS_UTC_OFFSET_HOURS"),
  do: config(:relay, stats_utc_offset_hours: String.to_integer(hours))

if ghosts = System.get_env("GHOSTS"), do: config(:relay, ghosts: String.to_integer(ghosts))
if max = System.get_env("RELAY_MAX"), do: config(:relay, max_players: String.to_integer(max))
