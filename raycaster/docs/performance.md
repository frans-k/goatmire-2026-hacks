# What it costs on the badge

Measurements of the renderer and of multiplayer, in the order they were made. The README says
what the game is; this says what AtomVM on the badge taught us while making it fast.

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

## Why a relay and not MQTT

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
