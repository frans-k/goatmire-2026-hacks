# Handing the game to a friend

One image, no passwords in it. It plays on any conference badge whose owner has joined
their wifi once in the badge's own firmware.

The image replaces the badge's firmware: the badge boots straight into the game until the
official firmware is flashed back (see "Going back").

## Make the image

From this directory, with Elixir and Erlang as in the README:

    RAYCASTER_WIFI_FROM_NVS=1 \
    RAYCASTER_RELAY=wss://evilgoat-relay.fly.dev \
    RAYCASTER_RELAY_TOKEN=$(cat ~/.config/goatmire/relay_token) \
    mix atomvm.packbeam

That writes `raycaster.avm` (about 57 KB). `RAYCASTER_WIFI_FROM_NVS=1` leaves every
compiled-in network out, `config/config_local.exs` too, and makes the game join the network
the badge already knows. Two things are in the image: the relay's address and its token. The
token is public on purpose (it only keeps casual visitors out of the relay), so the image is
fine to hand round. No password is in it. To check that, search the file for your own
network names and passphrases; there should be none.

## What the friend does

1. On the badge, in its own firmware, open Settings, then Wifi, and join a 2.4 GHz network.
   The badge remembers it, and reflashing over the firmware leaves that alone.
2. Plug the badge in and flash the image at the application address. With
   [esptool](https://github.com/espressif/esptool) 5:

       esptool --chip esp32s3 --port /dev/cu.usbmodem1101 write-flash 0x2b8000 raycaster.avm

   The port is `/dev/cu.usbmodem*` on macOS and `/dev/ttyACM*` on Linux. esptool 4 spells
   the command `write_flash`. The badge resets by itself and starts the game. On the test badge it had wifi about two
   seconds after boot and a slot on the relay at about four: the top line then says "online"
   and how many are playing.

Tested that way on a badge: it joined the network the firmware had saved, the certificate
validated, and it took a slot in a room on the relay.

If the badge has no saved network the game starts and you walk around alone. Its top line
says "offline".

## Going back

Flash the official badge firmware again, as its README says: check out
https://github.com/protolux-electronics/avm_badge and run `mix deps.get` and then
`mix atomvm.esp32.flash` with the badge plugged in. The saved wifi, profile and everything
else in NVS survives, both ways.

## Notes

- The badge needs the base image the official firmware installs (bootloader, VM, partition
  table). A badge that has had the official firmware flashed has it.
- Settings, Update in the official firmware fetches over the air; that is a separate route
  and not covered here.
