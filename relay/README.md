# relay

The server the raycaster badges play through. A badge joins, is put in a room of at
most eight by itself, says where it stands, and is sent one snapshot a second of
everyone in its room. Rooms are made and dropped as badges come and go, and nobody
is refused a room.

Why a server and not a broker: every message from another badge costs a badge about
ten milliseconds, so what a badge takes in has to be small however many are playing.
Here it is one message a second, from a server that does the sorting.

```sh
mix deps.get
mix run --no-halt            # port 4040, open to anyone who can reach it
mix test                     # 60 tests, 13 with real websocket clients
```

Open `http://localhost:4040/` to see who is in which room.

## Settings

Environment variables, read when it starts:

| | |
|---|---|
| `PORT` | the port badges connect to, 4040 |
| `RELAY_TOKEN` | a token a badge must send as `?token=...`, or anyone may join |
| `RELAY_MAX` | the most connections at once, in all rooms, 300 |
| `STATS_PATH` | the file the player counts are kept in, on a volume so a restart keeps them; without it they are counted in memory only |
| `STATS_UTC_OFFSET_HOURS` | where a day starts, from UTC, 2 |

Badges are built with `RAYCASTER_RELAY=ws://host:4040` and, if there is a token,
`RAYCASTER_RELAY_TOKEN=...` (letters, digits and `-_.~`). See `../raycaster`.

## The player dashboard

`GET /` is a page anyone can open: how many are playing now, and by day how many different badges played and the most at once. It asks `GET /stats.json` every ten seconds, which has the same numbers for anything else that wants them, and `GET /status` is the old one-line text. It shows counts, never ids.

The counts are kept in `STATS_PATH`, one line for each new badge in a day (`U 2026-10-01 A0F262EE6F6C`) and each new most-at-once (`P 2026-10-01 37`), and read back when the server starts. **The file holds chip ids**, which derive from a badge's MAC address, so it and the volume's snapshots are not for sharing; the dashboard and `stats.json` do not show them. Only twelve hex digits count as a badge, so test scripts with other names are left out. The id is what the badge says it is: it is a count of badges that claim to be different.

A machine's own disk is wiped on every restart and deploy, so on Fly the file lives on a volume (`[mounts]` in `fly.toml`, created by the first `fly deploy`, 1 GB, about $0.15 a month). One volume goes with one machine and one region, and it is tied to that server: Fly takes a snapshot every day and keeps it 5 days, so losing the server loses up to a day. Without `STATS_PATH`, or if its folder is missing, the dashboard says the counts are in memory only.

## Container

```sh
docker build -t evilgoat-relay .
docker run -d --name evilgoat-relay -p 4040:4040 -e RELAY_TOKEN=... evilgoat-relay
```

The image is about 500 MB because it is `elixir:slim` with the source compiled in,
not a release; the running server takes about 90 MB and next to no CPU with a few
players. A release on a smaller base would be a good deal smaller. Not done.

## On Fly.io

`fly.toml` runs it as a single small machine (shared cpu, 256 MB; the server takes
about 90 MB), with TLS ended by Fly, so badges use `wss://<app>.fly.dev`:

```sh
fly launch --no-deploy --copy-config    # the name in fly.toml may be taken
fly secrets set RELAY_TOKEN=...
fly deploy --ha=false
fly scale count 1
```

**Exactly one machine.** The rooms live in memory, so a second machine is a second
world, and Fly's default deploy makes two: hence `--ha=false`. It is never stopped
either, since a stopped relay is an absent one.

A badge connects to `wss://` about four seconds after it boots, with no wait for its
clock: tried on a badge on home wifi against `wss://goatmire-relay.fly.dev` (that app is now `evilgoat-relay`) with a
token, the driver said `Certificate validated`, the badge took a slot in room 1, and
three ghosts across the internet were in it with it. The firmware's chat waits for the
time before it connects, because a certificate is not yet valid at the epoch, and I
never saw the standalone game's clock read as set, so why it works is unexplained.

## What it protects, and what it does not

- The token is in every badge's firmware, so it keeps casual visitors out, not someone
  who reads the firmware. It is compared in constant time.
- What a badge sends is checked: a position must be a whole number inside the 16 by 16
  map, and at most one is taken from a badge every 200 ms. Anything it does not
  understand is ignored, and a frame that is not JSON does not hurt it.
- At most `RELAY_MAX` connections, so one client cannot make it hold unlimited sockets.
- **It is plain `ws://`.** There is no TLS here: put a reverse proxy in front for
  `wss://`. A token sent over plain `ws://` can be read by anyone on the path.
- A badge says who it is only by its slot, and there is nothing to stop someone
  joining several times to fill a room. No accounts, no names, no bans.

## The protocol

The part of Phoenix channels (serializer 2.0.0) a badge's chat client already speaks:
a frame is `[join_ref, ref, topic, event, payload]`, as JSON, over
`/badge/socket/websocket?vsn=2.0.0&chip=..&name=..&token=..`.

| badge sends | answer |
|---|---|
| `phx_join` on `raycaster:lobby` | `phx_reply` with `{"room": 3, "slot": 2, "max": 8}`, or an error `full` |
| `pos`, `{"x": 300, "y": 512}` | none |
| `respawn`, `{}` | none; a caught badge is back |
| `heartbeat` on `phoenix` | `phx_reply` ok |
| `phx_leave` | `phx_reply` ok |

Once a tick (a second) the server pushes `snap`,
`{"p": [[slot, x, y], ...], "g": [x, y, hunting]}`: everyone in the room who has said
where they are in the last five seconds and is not out, the badge itself included,
and the room's goat. A slot is who a player is and what colour they are drawn in.
`hunting` is 1 while the goat is after someone and 0 while it wanders. To a badge the
goat catches it pushes `caught`, `{}`.

`x` and `y` are in the map's fixed point, 256 to a cell, so 0 to 4095.

## The evil goat

Every room has a goat, `lib/relay/goat.ex`, moved here and drawn by the badges. It is
made with the room, in the open cell farthest from where the badges start, and goes
with it.

- It **wanders** at 250 (a badge walks at 800, in the same fixed point per second)
  to one random open cell after another, the shortest way through the cells.
- It **hunts** the nearest player it can see within eight cells, straight at them at
  330, rounding a corner if the straight line would clip one. It sees along the same
  quarter cell walk a badge uses to hide figures, so it sees you when you could see
  it.
- When it loses sight of them it **searches**: it goes to where it last saw them and
  stays there for four seconds, then wanders again. It does not follow anyone it
  cannot see.
- It **speeds up** to 350 wandering and 450 hunting while anyone in the room has
  lasted thirty seconds, and to 400 and 520 while anyone has lasted a minute,
  counted from the first position they sent after joining or coming back. It goes
  by whoever has lasted longest, so when they are caught, or leave, it slows down
  again. Before this it
  hunted at 600, which on a badge felt fast and hard to shake off.
- Nearer than half a cell to a player is a **catch**. The player is out: left out of
  the snapshot, told `caught`, and not listened to until they send `respawn`. Then
  they are at the start again, and safe from the goat for three seconds.

The goats move every `goat_ms` (100), and the time between steps is measured, so a
late timer moves them as far as the time it took. They are only sent in the
snapshot, so a badge sees the goat jump a second at a time. Catches are judged on the
last position a badge sent, which the badges send twice a second, so being caught
can come up to half a second after you think you got away.

The map is `priv/map.txt`, and `../raycaster` builds its engine from the same file,
so the goat and the badges cannot disagree about where the walls are. `Relay.Level`
has what the goat needs from it: open cells, sight, and the way from cell to cell.

To watch it on the laptop, run the server and
`elixir ../raycaster/scripts/relay_ghosts.exs ws://localhost:4040 4 60`: the ghosts
print where the goat is and whom it catches, and come back two seconds after being
caught. In 45 seconds with four ghosts it caught five times, searched, and wandered
off again between them.
