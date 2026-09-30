import Config

# Read when the server starts, also from a release. Only what is set is changed.
#
#   PORT          the port badges connect to (4040)
#   RELAY_TOKEN   a shared token a badge must send as ?token=..., or anyone may join.
#                 It is in every badge's firmware, so it keeps casual visitors out,
#                 not someone who reads the firmware
#   RELAY_MAX     the most connections at once, in all rooms (300)
if port = System.get_env("PORT"), do: config(:relay, port: String.to_integer(port))
if token = System.get_env("RELAY_TOKEN"), do: config(:relay, token: token)
if max = System.get_env("RELAY_MAX"), do: config(:relay, max_players: String.to_integer(max))
