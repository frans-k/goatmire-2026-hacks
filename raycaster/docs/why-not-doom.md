# Why not real Doom?

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
