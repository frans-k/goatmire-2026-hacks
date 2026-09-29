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
12 fps  ray 66.1 ms  push 9.7 ms  30 rects
```

`ray` is time spent casting rays and building the display list, `push` is time
the display took to accept the frame. The same line is drawn in the top corner.
Standing still with no key held, nothing is redrawn except that line, once a
second, so it reads 1 fps.

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

`lib/scene.ex` pushes whatever list it is handed. The game loop asks with a
`GenServer.call`, and [avm_scene](https://github.com/atomvm/avm_scene) answers
only after the display has taken the list, so the loop can never run ahead of the
screen and the call time is the display time.

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

**The display is not the bottleneck.** Pushing a frame takes about 10 ms. Casting
rays is around 85% of every frame, so the number of columns is the frame rate
knob (`@cols` in `lib/engine.ex`).

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

Done, but not yet measured on the badge (the tour in `lib/bench.ex` is the
measurement to make):

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

- The per column work is now the bigger share. Setting up a column (the
  12 argument `columns`, `cast`, two `axis_setup` and `colour`) is about 150
  instructions, mostly saving and restoring registers around the calls, against
  6 per ray step. Fewer calls and fewer live variables per column is the next
  thing to try.
- `step/4` still reads six small key lists as literals per frame.
- Overlap the display push with casting the next frame, and find out whether
  AtomVM runs two schedulers on this dual core chip
  (`:erlang.system_info(:schedulers_online)`). If it does, cast the two halves
  of the screen in two processes.
- Draw at 40 columns while moving and 80 while standing still. `@cols` is a
  module attribute today, so it would have to become an argument.

**Gameplay**

- There is only a room to walk around in: no goal, enemies or shooting, and the
  walls are flat colours, not textures.
- One map, hard-coded in `lib/engine.ex`. Loading maps, or letting Claude
  generate them, would need the map to come from outside the module.
- The fps line in the corner is a permanent debug readout. Make it a toggle.
- Sprites, and other badges as sprites over MQTT: each badge would publish its
  position and the others would draw it as a sprite. Not designed beyond that.
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
