# chat

The Mix app inside is called `my_hack`, which is why that name shows up in
modules, config keys and MQTT topics below.

A foundation for badge hacks: joins Wi-Fi, keeps an MQTT session alive, and
shows state on the display. `lib/app.ex` is the only module meant to be
rewritten; the rest is plumbing.

## Setup

Put your network in `config/config_local.exs` (gitignored, overrides
`config/config.exs`):

```elixir
import Config

config :my_hack, :wifi, ssid: "...", psk: "..."
# Optional, defaults to test.mosquitto.org, which is public:
config :my_hack, :topic_prefix, "goatmire/my_hack"
```

```sh
mix deps.get
mix atomvm.esp32.flash
mix atomvm.esp32.monitor --timeout 20
```

## Layout

```text
MyHack          entry point: screen, Wi-Fi, then App
MyHack.App      YOUR CODE. Receives link events and messages, drives the screen
MyHack.Link     MQTT session: subscribe, reconnect, presence (last will)
MyHack.Keyboard key matrix as a process, sends {:key, :down | :up, label} to App
MyHack.Keymap   matrix position -> key label
MyHack.Face     pixel-art expressions drawn next to the title
MyHack.Leds     the four LEDs from text (off, #rrggbb, or four colours), dimmed
MyHack.SK6812   LED driver over SPI (from exercise 5)
MyHack.Typing   key label -> typed character (Shift aware)
MyHack.Screen   display hardware setup + update/2
MyHack.Scene    pure model -> display list (status bar, title, lines)
MyHack.Wifi     association + DHCP with retries
MyHack.Badge    badge id from the factory MAC
```

Data flows one way through `App`:

```text
broker --> Link --{:message, sub, payload}--> App --update--> Screen/Scene
                <--------- Link.publish ------
```

## Topics

Base is `<topic_prefix>/<badge id>`; the badge prints it on startup.

| Topic | Direction | Meaning |
|---|---|---|
| `<base>/in/led` | to badge | LEDs: `off`, `#rrggbb` for all four, or four colours separated by spaces |
| `<base>/in/face` | to badge | expression: `neutral`, `happy`, `sad`, `surprised`, `thinking`, `sleepy`, `love` |
| `<base>/in/#` | to badge | anything else is shown in the log as `<name>: ...` |
| `<base>/out/<x>` | from badge | `Link.publish(link, "<x>", payload)` |
| `<base>/out/chat` | from badge | a line typed on the badge, sent with Enter |
| `<base>/out/status` | from badge | `online` (retained); `offline` via last will |

Try it:

```sh
mosquitto_sub -h test.mosquitto.org -t 'goatmire/my_hack/#' -v
mosquitto_pub -h test.mosquitto.org -t 'goatmire/my_hack/<id>/in/hello' -m 'world'
mosquitto_pub -h test.mosquitto.org -t 'goatmire/my_hack/<id>/in/ping' -n
```

## Chat

Type on the badge: the input line at the bottom fills up, Shift gives capitals
and symbols, Bksp deletes, Esc clears, Enter sends. Sent lines show as `me: ...`
in the log and go out on `<base>/out/chat`. Anything published to `<base>/in/<name>`
shows up as `<name>: ...`, so `in/chat` works as the other side of a conversation:

```sh
mosquitto_sub -h test.mosquitto.org -t 'goatmire/my_hack/<id>/out/chat' -v
mosquitto_pub -h test.mosquitto.org -t 'goatmire/my_hack/<id>/in/chat' -m 'hello badge'
```

## Scripts

Plain Elixir scripts that talk to the badge over MQTT from the laptop. They read
the broker and topic prefix from `config/`, so they follow the badge.

```sh
elixir scripts/log_messages.exs      # all traffic to log/my_hack.log, then: tail -f log/my_hack.log
elixir scripts/send_messages.exs <id> [count]   # numbered messages to a badge
elixir scripts/claude_chat.exs       # answers the badge's chat lines with Claude
```

`claude_chat.exs` wraps the `claude` CLI (your logged-in Claude Code, no API key)
with every tool disabled, since anyone who can publish to the broker can talk to
it. Claude answers in JSON, `{"say": "...", "leds": ["#rrggbb", ...], "face":
"happy"}`, and the script sends the words to `in/chat`, the colours to `in/led`
and the expression to `in/face`. It also knows the conference schedule
(https://goatmire.com/schedule.json) and the abstract of every talk (fetched
from the talk pages), refetched every 30 minutes and given to Claude as text in
its system prompt, together with the time in Sweden. So it can answer "what is on
at 10 tomorrow?" and "which talks are about LiveView?". That is about 10k tokens
per question, so it defaults to Sonnet; `--model haiku` is cheaper but less
accurate on times. The badge glows amber with a thinking face while
Claude works, then shows its mood. Replies are kept short to suit the screen, and a few turns of history are kept
per badge.

## Building on it

- **New behaviour**: edit `App`. Local inputs start from `App.init/1` and send it
  messages, as `MyHack.Keyboard` does.
- **New screen content**: add a key to the model in `Scene` and render it;
  `Screen.update(screen, %{key: value})` from anywhere.

## Known gaps

- Wi-Fi is only handled at boot; losing it later is not detected, so MQTT just
  keeps retrying.
- Only tested on a phone hotspot with test.mosquitto.org, which sometimes drops
  a fresh connection; `Link` reconnects on its own.
- Incoming text is converted from UTF-8 to the display font (`MyHack.Cp437`), so
  åäöé and friends work, but anything the font lacks (emoji, €) shows as `?`. Accented letters it lacks (Ł, ń,
  č, ...) are drawn as the plain letter.
  The keyboard has no way to type them yet.
