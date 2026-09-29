# raycaster

A Wolfenstein-style 3D view in pure Elixir, running on the Goatmire 2026 badge
under [AtomVM](https://atomvm.org). Walk around a small map with the badge
keyboard: arrows or W A S D to move and turn, Q and E to strafe.

It runs at 12 to 13 frames per second at 320x240, drawn as about 30 rectangles
per frame. No native code, no firmware changes: AtomVM stays the platform.

## Run it

Needs AtomVM already installed on the badge, see the workshop's first exercise.

```sh
mix deps.get
mix atomvm.esp32.flash
mix atomvm.esp32.monitor --timeout 20
```

The monitor prints, once a second:

```text
12 fps  ray 66.1 ms  push 9.7 ms  30 rects
```

`ray` is time spent casting rays and building the display list, `push` is time
the display took to accept the frame. The same line is drawn in the top corner.

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
| 40 columns | 66 ms | 10 ms | 12 to 13 |

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
`mix.exs`, flash, and read the monitor.

## Ideas

- The sine table is still a literal, read a few times per frame (about 1 ms in
  total). Passing it as an argument like the map would save that.
- Lower the view distance (`@max_steps`) so rays in open rooms stop early.
- Draw at 40 columns while moving and 80 while standing still.
- Sprites, and other badges as sprites over MQTT.

## Credits

`lib/keyboard.ex` and `lib/keymap.ex` are adapted from the workshop's keyboard
exercise, which reads the badge's 6x13 key matrix with interrupts.
