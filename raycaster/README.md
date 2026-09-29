# raycaster

A Wolfenstein-style 3D view in pure Elixir, running on the Goatmire 2026 badge
under [AtomVM](https://atomvm.org). Walk around a small map with the badge
keyboard: arrows or W A S D to move and turn, Q and E to strafe.

It runs at about 10 frames per second at 320x240 (7 to 13, depending on what
you are looking at), drawn as 15 to 40 rectangles per frame. No native code, no firmware changes: AtomVM stays the platform.

## Run it

Needs AtomVM already installed on the badge, see the workshop's first exercise.

```sh
mix deps.get
mix atomvm.esp32.flash
mix atomvm.esp32.monitor --timeout 20
```

The engine is plain integer maths, so its geometry is tested on the laptop with
`mix test`: known wall distances, staying on screen, collisions, turning. It
also draws a fixed tour of eight views and compares them with
`test/tour_frames.exs`, the frames the engine drew before it was sped up, so a
change meant only to be faster has to draw exactly the same picture.

The monitor prints, once a second:

```text
23 fps  ray 36.4 ms  wait 1.9 ms  20 rects
```

`ray` is time spent casting rays and building the display list. The display
takes each frame in a process of its own while the next is cast, and `wait` is
how long the game still had to wait for it before sending the next. The same
line is drawn in the top corner. Standing still with no key held, nothing is
redrawn except that line, once a second, so it reads 1 fps.

## How it works

`lib/engine.ex` is the whole renderer. For each of 40 columns across the screen
it casts a ray through a 16x16 map with a digital differential analysis (hop from
grid line to grid line until a wall is entered), turns the distance into a wall
height, and shades by distance. Neighbouring columns with the same height and
colour are merged into one rectangle. The result is a display list for
[AtomGL](https://github.com/atomvm/AtomGL): a rectangle each for the wall runs,
plus floor and ceiling.

Everything is integers. Positions are Q8 fixed point (256 is one map cell),
angles are 65536 to a turn, and the sine table is built while compiling on the
laptop.

`lib/scene.ex` pushes whatever list it is handed. A small process in
`lib/raycaster.ex` hands it each frame with a `GenServer.call`, which
[avm_scene](https://github.com/atomvm/avm_scene) answers only after the display
has taken the list. The game casts the next frame meanwhile, and waits for that
answer before sending another, so it can never run more than one frame ahead of
the screen.

## What I measured on the badge

| | ray casting | display push | frames per second |
|---|---|---|---|
| 80 columns, map looked up as a module attribute | 308 ms | 11 ms | 3 |
| 80 columns, map passed as an argument | 128 ms | 11 ms | 7 |
| 40 columns, standing still | 66 ms | 10 ms | 12 to 13 |
| 40 columns, walking around | 61 to 111 ms | 8 to 12 ms | 7 to 13, about 10 on average |

The first three rows were read standing at the spawn point, looking down the
longest corridor. The walking row is 29 one-second samples while moving and
turning around the map. Ray cost depends on how far the rays travel, so it moves
with the view, and the frame rate you get in play is the walking one.

Three things fall out of this.

**Casting is the cost, but the frame rate you read is not what you see.** Pushing
a frame takes about 10 ms, and casting rays is around 85% of every frame, so the
number of columns is the frame rate knob (`@cols` in `lib/engine.ex`). But on the
badge VM AtomGL answers a frame when it is *queued*, not when it is drawn, so
that 10 ms is the enqueue, and the fps line counts frames made, not frames shown.
See "Frames queued behind the panel" below.

**AtomVM copies a module literal onto the heap every time it is used.** The first
version read the map from a module attribute (`@grid`) for every step of every
ray. That table is 256 words, so each lookup copied it: 260 us, against 11 us
once the same tuple is passed in as an argument. In a tight loop it does worse
than slow: the benchmark ran the badge out of memory
(`Either OOM or invalid term while reading literals_table`). Fetch a big compile
time table once with a function and hand it down.

**The chip is slow, in a predictable way.** About 4 us per simple operation, 4 us
for an empty loop iteration, 14 us for a call with nine arguments: roughly a
million BEAM instructions a second. A ray of 15 steps costs about 1.6 ms, which
is why 80 columns cannot reach 15 frames per second.

`lib/bench.ex` reproduces the micro-benchmarks. Set `start: Raycaster.Bench` in
`mix.exs`, flash, and read the monitor. Before them it times the same fixed tour
the tests use, five frames per view, which is the number to compare when
changing the engine.

### After shortening the ray loop

Measured later, on AtomVM 0.8.0-dev. The micro-benchmarks came out faster than
above on this firmware (3 us for an empty loop, 10 us for a nine argument
call), so compare within this table rather than with the one above.

| | ray casting | display push | frames per second |
|---|---|---|---|
| Fixed tour, engine before the change | 41.8 ms | | |
| Fixed tour, engine after the change | 27.0 ms | | |
| Game, standing still | 26 to 31 ms | 7 to 10 ms | redraws once a second |
| Game, walking around | 55 to 84 ms | 9 to 14 ms | 2 to 13, 9 to 13 while walking steadily |

The renderer is 1.55 times faster and every view in the tour gained. Walking
did not get faster, and the reason is the keyboard, not the renderer: while a
key is held, `Raycaster.Keyboard` rescans the matrix every 20 ms, and one scan
took 18 to 22 ms (timed on the badge). The scanner and the game share the
chip, so the game gets about half of it and a walking frame takes twice as
long as a standing one. `ray` in the log is wall clock time, which is why the
scanning shows up there.

`Engine.step/4` also costs 3.2 ms a frame standing still and about 6 ms
walking, mostly the key lists it reads as literals.

### After trimming the work per column

Once a ray step was 6 instructions, the steps stopped mattering: the tour
averages 168 of them a frame, about 4 per column. Setting up each column was
the rest, so that was trimmed next, again drawing exactly the same frames.

| | fixed tour |
|---|---|
| Before any of this | 41.8 ms |
| Ray loop shortened | 27.0 ms |
| `cast` and `colour` inlined into the column loop | 23.7 ms |
| Per frame constants in one tuple, start cell worked out once, no tuple per axis | 21.0 ms |
| Right half of the screen cast in a second process | 15.4 ms |

AtomVM runs two schedulers here, one per core (the bench prints the count).
Drawing the tour twice took 336 ms in one process and 224 ms split across two,
about 1.5 times, not 2. So `frame/4` now spawns a process for the right half of
the screen each frame; that half is cast from the right edge inward, and the
two rectangles meeting at the seam are joined when they match, so the frames
are still exactly the same. With the cost of the spawn it gives 1.36 times.

In the game after all of this, standing still casts in 17 to 19 ms. Walking
casts in 27 to 35 ms most of the time (up to 57), because the keyboard scan
still takes its share, and the push stays at about 10 ms. Seconds of steady
walking read 16 to 22 fps, where they read 11 to 13 before; seconds with
stops in them read lower, since standing still redraws only once a second.

### Taking the display push off the game's path

Two more changes. `Engine.step/4` read its keys from lists of labels, which
are module literals, through `Enum.any?`: 3.0 ms a frame with nothing held on
the bench. It now matches the labels in function heads and keeps a bit per
direction: 1.06 ms with nothing held, 1.79 ms holding two keys.

And the display now takes each frame in a process of its own while the next
frame is cast, instead of the game waiting about 10 ms for it. The game now
waits 1.5 to 2.5 ms for the display. But pushing a frame costs CPU, not just
time on the wire, and both cores are already casting, so the rays got slower
by about as much: 33 to 41 ms while walking, against 27 to 35. Seconds of
steady walking read 20 to 24 fps, against 16 to 22. The chip is simply busy
now; the keyboard scan is the biggest thing left that is not drawing.
With two schedulers the keyboard scan could have run on the other core, yet
walking still halved the frame rate, so something in the scan holds up both.

### Frames queued behind the panel

Walking looked like 22 fps but the view kept moving for about a second after
releasing a key. AtomGL acknowledges a frame when it is put on its queue (32
deep, oldest dropped), not when it is drawn, so `GenServer.call` returns long
before the panel has drawn anything, and a game that casts faster than the panel
draws fills the queue and shows the past. The fps line counted frames made, not
frames shown, and the "push 10 ms" was only the enqueue.

The panel's real time for a frame turned out to be about 40 ms standing still and
about 65 ms while walking (18 to 74), when casting on both cores competes with
the task that draws. `Screen` now asks for 80 MHz, as the firmware does, which
helped, but the draw time is still longer than the 50 ms floor that was first
tried, so a floor could not fix it.

What does: AtomGL answers its font calls in queue order on the task that draws,
so asking it to drop a font that was never registered comes back only once every
earlier frame is on the panel. `present/2` makes that call after each frame, and
the game never casts more than one frame ahead of what is shown. The trail is
gone. The line in the corner now has `draw`, the time from handing a frame over to
seeing it on the panel; the `wait` next to it is how long the game had to stand
still for it.

Walking now reads 11 fps on average and 15 at best, casting in about 33 ms with
the panel taking 65: the panel, not the engine, is the limit. The earlier 18 to 22
fps were frames the game made and the panel never showed.

## Playing with others

Every badge running this joins the relay server (`../relay`), which puts it in a room
of at most eight by itself, tells it where the others are once a second, and is told
where it stands once a second. The others are drawn as small coloured figures, hidden
behind walls. Positions jump, once a second; that is what keeps it light. The line
under the fps one says `online, 3 playing`, or `offline` when there is no wifi or no
relay.

Give it your wifi in `config/config_local.exs`, which is not in git:

```elixir
import Config
config :raycaster, :wifi, ssid: "my network", psk: "my password"
```

and say where the relay is when building. Both are read while compiling, so a change
needs `mix compile --force`:

```sh
RAYCASTER_RELAY=wss://relay.example.com RAYCASTER_RELAY_TOKEN=... mix atomvm.esp32.flash
```

The wifi has to be 2.4 GHz. `wss://` gives TLS, checked against the certificates in the
VM's bundle; `ws://host:4040` is plain. A badge joins `wss://` about four seconds after
it boots, with no wait for its clock. A certificate is not yet valid at the epoch, and
the firmware's chat waits for the time before it connects, so that surprised me: the
wifi is given an SNTP host as the firmware's is, but I never saw the clock read as set
(`:erlang.system_time` said it was not), and the certificate was accepted regardless. I
do not know why. Without wifi or a relay the game starts as before and you walk around
alone. Joining wifi happens
beside the game, so it never waits for it.

To try it with one badge, run the relay on the laptop (`cd ../relay && mix run
--no-halt`) and three ghosts against it, with the badge on the same network:

```sh
elixir scripts/relay_ghosts.exs ws://localhost:4040 3 120   # RELAY_TOKEN=... if it asks
```

A badge says where it stands (`x` and `y`, in the map's fixed point) and the relay
sends back `{"p": [[slot, x, y], ...]}`, everyone in the room; a slot is who a player
is and what colour it is drawn in. The frames are in `lib/relay_wire.ex`, tested on the
laptop and, by the ghosts, against the real server; `lib/relay_link.ex` keeps the
websocket. Figures are hidden by a walk along the line to them, a quarter cell at a
time, not by a ray per column, so someone half behind a corner is either seen or not.
One off to the side is skipped before that walk.

The relay has no accounts, only a shared token that is in every badge's firmware, and
the badge takes its word for nothing: a position must be a whole number inside the
map. See `../relay/README.md` for what it does and does not protect.

### Why a relay and not MQTT

An earlier version of this used an MQTT broker, which makes every badge take in every
other badge's messages, and each one costs about ten milliseconds of a chip that does
a million instructions a second. MQTT is gone now. Measured turning on the spot (the
`RAYCASTER_AUTOPILOT=1` build switch, so every run casts the same views), with the
MQTT version at two updates a second and the others carried along between them:

| | fps | ray casting | drawing |
|---|---|---|---|
| alone, no network | 19.2 | 25.4 ms | 49.8 ms |
| MQTT, nobody else | 17.2 | 29.4 ms | 53.7 ms |
| MQTT, 8 others | 13.2 | 54.0 ms | 65.5 ms |
| relay, nobody else | 17.5 | 30.5 ms | 52.3 ms |
| relay, 8 others | 16.3 | 39.2 ms | 54.1 ms |

At five updates a second, 8 others took MQTT from 19 to 9 fps. With a relay the
sorting is done on the server, so a badge hears one message a second however many
others there are, and what is left with 8 others is drawing them, about a millisecond
each. MQTT needed no server of its own, but it has no rooms, costs more for every
player, and its client alone (18.7 KB) does not fit the firmware's image.

### In the official badge firmware

**It does not fit yet.** The firmware's `main.avm` slot is 671,744 bytes and its
packed app is 663,220, so there is 8.5 KB to spare. A page with this engine alone
added 10,512 bytes when measured, 2 KB over, and with multiplayer and amqtt the
image was 706,456 bytes, 43,236 more than the firmware's. An image over the slot is
cut off when it is loaded, and the badge crashes at boot. Multiplayer is only in
this project for now.

## Why not real Doom?

The question this started from: how do people run Doom on odd hardware, and can
the badge do something along those lines without replacing AtomVM?

- **Port the engine.** Doom is portable C, and
  [doomgeneric](https://github.com/klange/doomgeneric) reduces a port to five
  functions: init, draw a frame, read keys, sleep, and the tick count. Anything
  with a framebuffer, input and a few megabytes of RAM qualifies.
- **Stream it.** The game runs elsewhere and the device is only a screen and
  controller. [1-Bit Doom](https://www.sanderdesnaijer.com/projects/1-bit-doom)
  runs Doom in a browser and sends dithered 128x64 frames (1 KB each) to an
  ESP32 OLED over WebSocket at 15 to 20 fps.
- **Emulate.** Put a CPU emulator on the device and run Doom inside it.

Native Doom does not fit this badge. The ESP32-S3 ports, like
[esp32-doom](https://github.com/arkadijs/esp32-doom), want at least 4 MB of PSRAM
and around 16 MB of flash for the app and the game data; the badge has 2 MB and
4 MB, and those ports replace the firmware rather than run on AtomVM.

Streaming would work in principle. AtomGL has an `image` primitive,
`{:image, X, Y, Background, {Format, Width, Height, Pixels}}`, but its
[primitives documentation](https://github.com/atomvm/AtomGL/blob/main/docs/primitives.md)
only shows `rgba8888`, which is 77 KB per frame at 160x120. Whether other formats
exist, and how fast the badge can take frames over Wi-Fi, is untested.

So this is the other route: a Doom-like written entirely in Elixir, drawn with the
`rect` primitive the display already handles well.

## Todo

Ray casting is around 85% of every frame, so most of the speed is in the first
group.

**Speed**

Done, and measured above (the fixed tour went from 41.8 to 27.0 ms a frame):

- The ray step loop is 6 BEAM instructions instead of about 37. The bounds
  check and the step limit are gone, because the map's outer wall stops every
  ray (a test checks the border stays closed), and the cell is one index into
  the grid tuple instead of an x and a y.
- No module literals are read while drawing. The sine table and the wall
  colours are functions returning plain integers, which the compiler makes
  into jump tables.
- The "no wall crossing" distance was `1 <<< 28`, past the 28 bit integers
  AtomVM keeps unboxed on this chip. It is `1 <<< 26` now.

Next:

- The column setup was trimmed (21.0 ms a frame, see above). What is left per
  column is mostly the arithmetic itself; a table of shaded colours passed in
  like the map would save the shading, perhaps 10%.
- The keyboard scan takes about half the chip while a key is held (see above),
  and with both cores busy drawing it is now the biggest cost left.
  Scanning less often, only the rows with game keys, or with less work per row
  would give it back. Left for now, because the input may change.
- The second process is spawned afresh every frame, which copies the map into
  it each time. A worker that lives for the whole game and keeps its own copy
  of the map could get closer to the 1.5 times two processes allow, perhaps
  1 ms a frame.
- Draw at 40 columns while moving and 80 while standing still. `@cols` is a
  module attribute today, so it would have to become an argument.

**Gameplay**

- There is only a room to walk around in: no goal, enemies or shooting, and the
  walls are flat colours, not textures.
- One map, hard-coded in `lib/engine.ex`. Loading maps, or letting Claude
  generate them, would need the map to come from outside the module.
- The fps line in the corner is a permanent debug readout. Make it a toggle.
- Make it a mode of the chat badge (`../chat`), switched by a key, instead of a
  separate firmware.

**Not verified**

- The badge's key matrix may have no diodes, in which case holding three keys at
  once (forward, turn and strafe) can produce ghost keys. The controls were
  confirmed to work, but not with several keys held at once.
- Whether AtomGL can take frames in a format other than `rgba8888`, and how fast
  the badge can receive them over Wi-Fi. This decides whether streaming real Doom
  to the badge would work (see above).

**Housekeeping**

- Only `Raycaster.Engine` has tests. The game loop, screen and keyboard need the
  badge, and there is no CI.
- The repo has no LICENSE, and the keyboard code is copied into both `chat/` and
  `raycaster/` from the workshop exercise, which has none either. The credit
  below is the only record of where it came from.

## Credits

`lib/keyboard.ex` and `lib/keymap.ex` are adapted from the workshop's keyboard
exercise, which reads the badge's 6x13 key matrix with interrupts.
