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
mix test                     # 36 tests, 11 with real websocket clients
```

Open `http://localhost:4040/` to see who is in which room.

## Settings

Environment variables, read when it starts:

| | |
|---|---|
| `PORT` | the port badges connect to, 4040 |
| `RELAY_TOKEN` | a token a badge must send as `?token=...`, or anyone may join |
| `RELAY_MAX` | the most connections at once, in all rooms, 200 |

Badges are built with `RAYCASTER_RELAY=ws://host:4040` and, if there is a token,
`RAYCASTER_RELAY_TOKEN=...` (letters, digits and `-_.~`). See `../raycaster`.

## Container

```sh
docker build -t goatmire-relay .
docker run -d --name goatmire-relay -p 4040:4040 -e RELAY_TOKEN=... goatmire-relay
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

Nothing here has been deployed. `wss://` on a badge needs its clock set, because a
certificate is not yet valid at the epoch: the firmware's chat waits for the time
before it connects, and the standalone game does not set it yet.

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
| `heartbeat` on `phoenix` | `phx_reply` ok |
| `phx_leave` | `phx_reply` ok |

Once a tick (a second) the server pushes `snap`, `{"p": [[slot, x, y], ...]}`: everyone
in the room who has said where they are in the last five seconds, the badge itself
included. A slot is who a player is and what colour they are drawn in.

`x` and `y` are in the map's fixed point, 256 to a cell, so 0 to 4095.
