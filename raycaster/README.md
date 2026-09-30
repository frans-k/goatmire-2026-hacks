# raycaster

A Wolfenstein-style 3D view in pure Elixir, running on the Goatmire 2026 badge under
[AtomVM](https://atomvm.org). Walk around a small maze, alone or with up to seven other
badges over wifi. No native code, no firmware changes: AtomVM stays the platform.

It runs at about 10 frames per second at 320x240 (7 to 13, depending on what you are
looking at), drawn as 15 to 40 rectangles per frame.

## Playing

The game starts in a menu: Play, Controls, Status. Up and Down (or W and S) move, Enter or
Space picks, Esc goes back.

In the game:

| Key | |
|---|---|
| Arrows or W A S D | move and turn |
| Q and E | strafe |
| Esc | back to the menu |

Being in the menu means being out of the game. The badge leaves the relay's room, so nobody
sees it and the goat cannot catch it, and Play starts a new life in a room, with the count
from zero. The badge does not join a room until the first Play. Status shows the wifi, the
relay and the badge id; the passphrase is never drawn.

Without wifi or a relay you walk around alone. With them you see the others as small
coloured figures, and the relay's evil goat hunts everyone in the room (see "Playing with
others").

## Run it

Needs AtomVM already installed on the badge, see the workshop's first exercise.

```sh
mix deps.get
mix atomvm.esp32.flash
mix atomvm.esp32.monitor --timeout 20
```

Build switches, all read while compiling, so a change needs `mix compile --force`:

| Variable | Effect |
|---|---|
| `RAYCASTER_RELAY`, `RAYCASTER_RELAY_TOKEN` | the relay to play on and the token it asks for |
| `RAYCASTER_WIFI_FROM_NVS=1` | leave every compiled-in network out and join the wifi the badge's own firmware saved, see [docs/sharing.md](docs/sharing.md) |
| `RAYCASTER_STATS=1` | draw the fps line in the top corner too |
| `RAYCASTER_GOAT=1` | a goat stands hunting at the end of the corridor, to look at without a relay |
| `RAYCASTER_OFFLINE=1` | leave the network out whatever else is set |
| `RAYCASTER_AUTOPILOT=1` | turn on the spot and skip the menu, so every run casts the same views (for measuring) |

The monitor prints, once a second:

```text
23 fps  ray 36.4 ms  wait 1.9 ms  20 rects
```

`ray` is time spent casting rays and building the display list. The display takes each frame
in a process of its own while the next is cast, and `wait` is how long the game still had to
wait for it before sending the next. Standing still with no key held, nothing is redrawn
except the status lines, once a second, so it reads 1 fps.

### Tests

The engine is plain integer maths, so `mix test` checks it on the laptop: known wall
distances, staying on screen, collisions, turning. It also draws a fixed tour of eight views
and compares them with `test/tour_frames.exs`, the frames the engine drew before it was sped
up, so a change meant only to be faster has to draw exactly the same picture. The menu, the
game over screen, the LED patterns, the relay's wire format and the wifi choice are pure and
tested the same way. The game loop, screen and keyboard need the badge.

## How it works

`lib/engine.ex` is the whole renderer. For each of 40 columns across the screen it casts a
ray through a 16x16 map with a digital differential analysis (hop from grid line to grid
line until a wall is entered), turns the distance into a wall height, and shades by
distance. Neighbouring columns with the same height and colour are merged into one
rectangle. The result is a display list for [AtomGL](https://github.com/atomvm/AtomGL): a
rectangle each for the wall runs, plus floor and ceiling.

Everything is integers. Positions are Q8 fixed point (256 is one map cell), angles are 65536
to a turn, and the sine table is built while compiling on the laptop. The map is
`../relay/priv/map.txt`, read while compiling, so the relay's goat walks the same walls.

`lib/scene.ex` pushes whatever list it is handed. A small process in `lib/raycaster.ex`
hands it each frame with a `GenServer.call`, which
[avm_scene](https://github.com/atomvm/avm_scene) answers only after the display has taken
the list. The game casts the next frame meanwhile, and waits for that answer before sending
another, so it can never run more than one frame ahead of the screen.

| File | |
|---|---|
| `lib/raycaster.ex` | the game loop: menu, play, game over, and the network beside them |
| `lib/engine.ex` | rays, walls, figures, the goat, respawn |
| `lib/menu.ex`, `lib/game_over.ex` | the two screens around the game, pure |
| `lib/relay_link.ex`, `lib/relay_wire.ex` | the websocket to the relay, and the frames it speaks |
| `lib/omen.ex`, `lib/sk6812.ex` | the LEDs that warn you about the goat |
| `lib/keyboard.ex`, `lib/keymap.ex`, `lib/wifi.ex`, `lib/screen.ex` | the badge's own hardware |
| `lib/bench.ex` | micro-benchmarks; set `start: Raycaster.Bench` in `mix.exs` |

What the badge taught us about speed (module literals copied onto the heap, a chip that does
about a million instructions a second, frames queued behind the panel) is in
[docs/performance.md](docs/performance.md).

## Playing with others

Every badge that has pressed Play joins the relay server (`../relay`), which puts it in a
room of at most eight by itself, tells it where the others are once a second, and is told
where it stands twice a second. The others are drawn as small coloured figures, hidden
behind walls; their positions jump once a second, which is what keeps it light. The line
under the fps one says `online, 3 playing`, or `offline` when there is no wifi or no relay.

Give it your wifi in `config/config_local.exs`, which is not in git:

```elixir
import Config
config :raycaster, :wifi, ssid: "my network", psk: "my password"
```

and say where the relay is when building:

```sh
RAYCASTER_RELAY=wss://relay.example.com RAYCASTER_RELAY_TOKEN=... mix atomvm.esp32.flash
```

The wifi has to be 2.4 GHz. `wss://` gives TLS, checked against the certificates in the VM's
bundle; `ws://host:4040` is plain. A badge joins `wss://` about four seconds after it boots,
with no wait for its clock. That is odd: a certificate is not yet valid at the epoch, and the
firmware's chat waits for the time before it connects. The wifi is given an SNTP host as the
firmware's is, but the clock never read as set and the certificate was accepted regardless.
Why is not known. Joining wifi happens beside the game, so the game never waits for it.

To try it with one badge, run the relay on the laptop (`cd ../relay && mix run --no-halt`)
and three ghosts against it, with the badge on the same network:

```sh
elixir scripts/relay_ghosts.exs ws://localhost:4040 3 120   # RELAY_TOKEN=... if it asks
```

A badge says where it stands (`x` and `y`, in the map's fixed point) and the relay sends back
`{"p": [[slot, x, y], ...], "g": [x, y, hunting]}`: everyone in the room, by slot, which is
also the colour, and the goat. The badge takes the server's word for nothing: a position must
be a whole number inside the map, and a snapshot with anything odd in it is refused whole.
The relay has no accounts, only a shared token that is in every badge's firmware. See
`../relay/README.md` for what it protects and what it does not.

Figures are hidden by a walk along the line to them, a quarter cell at a time, not by a ray
per column, so someone half behind a corner is either seen or not. One off to the side is
skipped before that walk.

### The evil goat

Every room has a goat on the relay that hunts the players; how it moves, and how it speeds up
and calms down, is in `../relay/README.md`. On the badge:

- `Engine.sprites` takes `{:goat, x, y, hunting}` beside the players and draws a goat facing
  you: body, head, ears, curling horns, beard, legs, and eyes that are yellow, and red while
  it hunts or searches. It is thirteen rectangles near and five far off, and hides behind
  walls like anyone.
- On `caught` the game draws `Raycaster.GameOver` once: the goat up close on dark red, "GAME
  OVER", how long you lasted, and "Press any key". Keys are ignored for the first 1.5
  seconds, so one held while running does not skip it. A key sends `respawn` and starts again
  at one of two spawn points, the start or the far corner (`Engine.respawn/1`), whichever is
  farther from the goat. Both face at least eight cells down a corridor, which a test checks.
  The line under the fps one says how long you have been alive.
- The four LEDs warn you, through walls, before you see it (`lib/omen.ex`): dark while the
  goat is more than seven cells off, a dark red ember crawling across them within seven, red,
  purple and orange shifting round within four, a red and white strobe within two while it
  hunts, and steady red under the game over screen. A process of its own plays the pattern
  from frames encoded once, and the game only tells it when the level changes. The driver is
  the chat badge's (`lib/sk6812.ex`), on `spi3`, beside the display's `spi2`. The LEDs have
  not been checked on a badge.
- A badge comes back by itself when the relay restarts. The websocket driver says it
  reconnects on its own, but after the server closed the connection it said `closed :normal`
  twice and never tried again, and a position sent while it was down came back as a bare
  `:not_connected`, which crashed the link. So on a close `RelayLink` closes it too and opens
  a new one three seconds later, and any refusal to send is only logged. With the relay
  stopped for five seconds, a badge was back in its room about four seconds after the relay
  was.

What the goat costs in fps, and what sending twice a second costs, has not been measured.

## Giving it to others

- **A friend's badge:** one image with no password in it, which joins the wifi the badge's
  own firmware saved: [docs/sharing.md](docs/sharing.md).
- **The official firmware:** a page in `avm_badge` itself is a draft PR (#49). The firmware's
  `main.avm` slot is 671,744 bytes, and as of 2026-09-30 upstream `main` leaves about 2.5 KB
  of it free, so a page of this size (around 12 KB, 22 KB with multiplayer) does not fit
  unless something else shrinks. How to measure that, and to update the PR:
  [docs/avm-badge-firmware.md](docs/avm-badge-firmware.md).
- **The app store:** the store's apps are separate signed packs loaded from wifi, and this
  game fits one (about 34 KB of the 64 KB allowed). That port is a pull request to the
  store's apps repo, not code in this folder.

## Why not real Doom?

Native Doom does not fit this badge (2 MB of PSRAM and 4 MB of flash, against ports that want
4 MB and 16 MB and replace the firmware), so this is a Doom-like written entirely in Elixir
and drawn with the `rect` primitive the display already handles well. The options that were
looked at are in [docs/why-not-doom.md](docs/why-not-doom.md).

## Todo

**Speed.** Ray casting is around 85% of every frame. Measured so far is in
[docs/performance.md](docs/performance.md); what is left:

- The column setup was trimmed (21.0 ms a frame on the fixed tour). What is left per column
  is mostly the arithmetic itself; a table of shaded colours passed in like the map would
  save the shading, perhaps 10%.
- The keyboard scan takes about half the chip while a key is held, and with both cores busy
  drawing it is now the biggest cost left. Scanning less often, only the rows with game keys,
  or with less work per row would give it back.
- The second process is spawned afresh every frame, which copies the map into it each time. A
  worker that lives for the whole game and keeps its own copy could get closer to the 1.5
  times two processes allow, perhaps 1 ms a frame.
- Draw at 40 columns while moving and 80 while standing still. `@cols` is a module attribute
  today, so it would have to become an argument.

**Gameplay**

- The walls are flat colours, not textures.
- One map, built into `lib/engine.ex` while compiling. Loading maps at run time would need the
  badge to get the map from outside the module, and the relay's goat to walk it too.
- More goats in bigger rooms, a goat of your own offline, and moving the goat smoothly
  between snapshots.
- Make it a mode of the chat badge (`../chat`), switched by a key, instead of a separate
  firmware.

**Not verified**

- The badge's key matrix may have no diodes, in which case holding three keys at once
  (forward, turn and strafe) can produce ghost keys. The controls were confirmed to work, but
  not with several keys held at once.
- Whether AtomGL can take frames in a format other than `rgba8888`, and how fast the badge can
  receive them over Wi-Fi. This decides whether streaming real Doom to the badge would work.
- The LEDs, as above, and the goat's cost in fps.

**Housekeeping**

- There is no CI.
- The repo has no LICENSE, and the keyboard code is copied into both `chat/` and `raycaster/`
  from the workshop exercise, which has none either. The credit below is the only record of
  where it came from.

## Credits

`lib/keyboard.ex` and `lib/keymap.ex` are adapted from the workshop's keyboard exercise, which
reads the badge's 6x13 key matrix with interrupts. `lib/sk6812.ex` is adapted from
`../chat/lib/sk6812.ex`, which drives the LEDs with the SPI peripheral as a waveform
generator.
