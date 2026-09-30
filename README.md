# goatmire-2026-hacks

Things made with the Goatmire 2026 badge and [AtomVM](https://atomvm.org). Each
folder is a standalone Mix project that runs on the badge.

| Folder | What it is |
|---|---|
| [`raycaster/`](raycaster) | A Wolfenstein-style 3D view in pure Elixir, about 10 fps, with measurements of what AtomVM costs on the badge |
| [`relay/`](relay) | The websocket server the raycaster badges play through: rooms of eight, a player dashboard, and the evil goat. Runs on Fly.io |
| [`chat/`](chat) | Type on the badge and chat over MQTT. Wi-Fi, a reconnecting MQTT link, a pixel-art face and LEDs on the badge; a laptop script lets Claude answer, glow and make faces, with the conference schedule as context |
