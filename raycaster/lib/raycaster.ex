defmodule Raycaster do
  @moduledoc """
  Walk around a small map with the badge keyboard.

  Arrows or W A S D move and turn, Q and E strafe. Once a second it prints
  frames per second and where the time went (casting rays, or waiting for the
  display), and shows the same on screen.

  The display takes a frame in a process of its own, `present/2`, so the next
  frame is cast while the last one is still going out. The game only waits
  when it has a new frame ready before the display has finished the last.

  With no key held and the view already on screen, it draws nothing and waits
  for a key, redrawing once a second only to update that line.

  Built with `RAYCASTER_RELAY=wss://host` and wifi credentials in
  `config/config_local.exs` it also joins the relay server (see `../relay`), which
  puts it in a room of at most eight, tells it where the others are once a second,
  and is told where it is. The others are drawn as coloured figures. Without them
  it is a room to walk around in alone, and the game starts at once either way:
  wifi is joined in a process of its own.
  """

  alias Raycaster.{Engine, Keyboard, RelayLink, RelayWire, Screen, Wifi}

  # Read while compiling on the laptop: the badge never sees Application at all.
  @ssid Application.compile_env!(:raycaster, [:wifi, :ssid])
  @psk Application.compile_env!(:raycaster, [:wifi, :psk])

  # The relay server, and its token if it asks for one, see config/config.exs.
  @relay Application.compile_env!(:raycaster, :relay)
  @relay_token Application.compile_env!(:raycaster, :relay_token)

  # Turns on the spot by itself, for measuring, see config/config.exs.
  @autopilot Application.compile_env!(:raycaster, :autopilot)

  # A goat standing still, to look at, see config/config.exs.
  @goat Application.compile_env!(:raycaster, :goat)

  @report_ms 1000

  # How often to say where we are. The relay hands out one snapshot a second and
  # forgets a badge that is quiet for five seconds, so this is all it needs.
  @announce_ms 1_000

  def start do
    {:ok, scene, display} = Screen.start()
    {:ok, _keyboard} = Keyboard.start_link()

    IO.puts("raycaster: #{Engine.cols()} columns, #{Screen.width()}x#{Screen.height()}")

    # Fetched once and passed around: AtomVM copies a module literal every time
    # it is used, so looking the map up per frame (or per ray step) is ruinous.
    grid = Engine.grid()

    presenter = spawn_link(fn -> present(scene, display) end)

    id = hex(chip_id())
    IO.puts("raycaster: badge #{id}")

    net = %{link: nil, up: false, others: [], sent: nil}
    if @ssid != nil and @relay != nil, do: go_online(self(), id)

    now = now()

    stats = %{
      at: now,
      frames: 0,
      ray: 0,
      wait: 0,
      draw: 0,
      hud: "",
      drawn: nil,
      others: nil,
      showing: false
    }

    loop(presenter, grid, Engine.new(), [], now, stats, net)
  end

  # Joins wifi and then the relay, apart from the game, which cannot wait the
  # up to 30 seconds and five tries that joining can take. Not linked to it, and
  # trapping exits: the network is optional, so nothing that goes wrong in it may
  # take the game down, only be said. The link is started here, so it lives as
  # long as this process.
  defp go_online(game, id) do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      IO.puts("Connecting to #{@ssid}...")

      case Wifi.connect(@ssid, @psk) do
        {:ok, address} ->
          IO.puts("Wifi up, #{address}")
          start_link(game, id)
          watch(game, id)

        {:error, reason} ->
          IO.puts("Wifi failed: #{inspect(reason)}, playing alone")
      end
    end)
  end

  defp start_link(game, id) do
    case link(game, id) do
      {:ok, link} -> send(game, {:link_pid, link})
      other -> IO.puts("Relay link did not start: #{inspect(other)}")
    end
  end

  defp link(game, id),
    do: RelayLink.start_link(owner: game, base: @relay, chip: id, token: @relay_token)

  # Says why the link died, if it does, and starts it again a little later.
  defp watch(game, id) do
    receive do
      {:EXIT, pid, reason} ->
        IO.puts("Relay link #{inspect(pid)} died: #{inspect(reason)}")
        send(game, {:link, :down})
        :timer.sleep(5_000)
        start_link(game, id)
        watch(game, id)

      _other ->
        watch(game, id)
    end
  end

  defp figures([]), do: []
  defp figures([{slot, x, y} | rest]), do: [{x, y, RelayWire.colour(slot)} | figures(rest)]

  defp chip_id do
    case :esp.get_default_mac() do
      {:ok, mac} -> mac
      _other -> <<0, 0, 0, 0, 0, 0>>
    end
  end

  defp hex(<<>>), do: <<>>

  defp hex(<<byte, rest::binary>>),
    do: <<digit(div(byte, 16)), digit(rem(byte, 16)), hex(rest)::binary>>

  defp digit(n) when n < 10, do: ?0 + n
  defp digit(n), do: ?A + n - 10

  defp loop(presenter, grid, player, held, last, stats, net) do
    {held, net} = drain(held, net)
    held = if @autopilot, do: ["Right"], else: held

    {held, last, net} =
      if held == [] and player == stats.drawn and net.others == stats.others do
        idle(stats.at + @report_ms - now(), net)
      else
        {held, last, net}
      end

    t0 = now()
    player = Engine.step(grid, player, held, t0 - last)
    net = announce(net, player, t0)

    others = if @goat, do: [{:goat, 10 * 256 + 128, 384, true} | net.others], else: net.others
    items = Engine.sprites(grid, player, others, Screen.width(), Screen.height())
    items = items ++ Engine.frame(grid, player, Screen.width(), Screen.height())
    t1 = now()

    # One frame at a time goes to the display: wait for the last one if it is
    # still going out.
    draw = shown(stats.showing)
    t2 = now()
    send(presenter, {:frame, self(), [hud(stats.hud), status(net) | items]})

    stats = %{
      stats
      | frames: stats.frames + 1,
        ray: stats.ray + t1 - t0,
        wait: stats.wait + t2 - t1,
        draw: stats.draw + draw,
        drawn: player,
        others: net.others,
        showing: true
    }

    loop(presenter, grid, player, held, t0, report(stats, t2, length(items)), net)
  end

  # Says where we are, when it is time.
  defp announce(%{up: true, link: link} = net, player, now) when link != nil do
    if net.sent == nil or now - net.sent >= @announce_ms do
      RelayLink.publish(link, player.x, player.y)
      %{net | sent: now}
    else
      net
    end
  end

  defp announce(net, _player, _now), do: net

  defp status(%{up: true, others: others}), do: line("online, #{length(others) + 1} playing")

  defp status(%{link: nil}) do
    cond do
      @relay == nil -> line("offline")
      @ssid == nil -> line("offline")
      true -> line("joining wifi")
    end
  end

  defp status(_net), do: line("connecting")

  defp line(text), do: {:text, 4, 24, :default16px, 0x00FF00, 0x000000, text}

  # How long the last frame took from being handed over to being on the panel.
  defp shown(false), do: 0
  defp shown(true), do: receive(do: ({:shown, ms} -> ms))

  # AtomGL answers a frame when it is queued, not when it is drawn, and keeps
  # up to 32, so a call to avm_scene says nothing about the panel. Its calls to
  # the font registry are answered in queue order by the task that draws, so
  # asking it to drop a font that was never there comes back only after every
  # frame before it is on the panel. That is what :shown means: the game can
  # never be more than one frame ahead of what is shown, and the time it took
  # is the panel's real time for a frame.
  defp present(scene, display) do
    receive do
      {:frame, from, items} ->
        t0 = now()
        :ok = GenServer.call(scene, {:frame, items}, 5_000)
        :port.call(display, {:deregister_font, :sync}, 5_000)
        send(from, {:shown, now() - t0})
        present(scene, display)
    end
  end

  # Nothing to draw until a key goes down, someone else moves, or until the line
  # in the corner is due. The clock restarts here, so the time spent waiting is
  # not taken for one long frame and the first step after it does not jump.
  defp idle(timeout, net) do
    receive do
      {:key, :down, label} -> {[label], now(), net}
      {:key, :up, _label} -> idle(timeout, net)
      {:link_pid, _link} = message -> {[], now(), heard(message, net)}
      {:link, _status} = message -> {[], now(), heard(message, net)}
      {:players, _list} = message -> {[], now(), heard(message, net)}
    after
      max(timeout, 0) -> {[], now(), net}
    end
  end

  # Keys held right now: a press adds, a release removes. Whatever the relay has
  # said meanwhile is taken in too. Only its own messages are matched: the
  # display's `:shown` is in this mailbox as well, and is not this function's.
  defp drain(held, net) do
    receive do
      {:key, :down, label} -> drain([label | :lists.delete(label, held)], net)
      {:key, :up, label} -> drain(:lists.delete(label, held), net)
      {:link_pid, _link} = message -> drain(held, heard(message, net))
      {:link, _status} = message -> drain(held, heard(message, net))
      {:players, _list} = message -> drain(held, heard(message, net))
    after
      0 -> {held, net}
    end
  end

  defp heard({:link_pid, link}, net), do: %{net | link: link}
  defp heard({:link, :up}, net), do: %{net | up: true, sent: nil}
  defp heard({:link, :down}, net), do: %{net | up: false, others: []}

  # The relay's snapshot is everyone else in the room, ready to draw: a slot is a
  # colour, and there is nothing to carry along and nothing to expire.
  defp heard({:players, players}, net), do: %{net | others: figures(players)}

  defp report(%{frames: frames} = stats, now, rects) when now - stats.at >= @report_ms do
    # Rounded, so that standing still (one frame in a little over a second)
    # reads 1 and not 0.
    elapsed = now - stats.at
    fps = div(frames * 1000 + div(elapsed, 2), elapsed)
    ray = div(stats.ray * 10, max(frames, 1))
    wait = div(stats.wait * 10, max(frames, 1))
    draw = div(stats.draw * 10, max(frames, 1))

    line =
      "#{fps} fps  ray #{tenths(ray)} ms  wait #{tenths(wait)} ms  draw #{tenths(draw)} ms  #{rects} rects"

    IO.puts(line)
    %{stats | at: now, frames: 0, ray: 0, wait: 0, draw: 0, hud: line}
  end

  defp report(stats, _now, _rects), do: stats

  defp tenths(n), do: "#{div(n, 10)}.#{rem(n, 10)}"

  defp hud(text), do: {:text, 4, 4, :default16px, 0xFFFF00, 0x000000, text}

  defp now, do: :erlang.monotonic_time(:millisecond)
end
