defmodule Raycaster do
  @moduledoc """
  Walk around a small map with the badge keyboard.

  Arrows or W A S D move and turn, Q and E strafe. Once a second it prints
  frames per second and where the time went (casting rays, or waiting for the
  display), and shows the same on screen.

  The display takes a frame in a process of its own, `present/1`, so the next
  frame is cast while the last one is still going out. The game only waits
  when it has a new frame ready before the display has finished the last.

  With no key held and the view already on screen, it draws nothing and waits
  for a key, redrawing once a second only to update that line.
  """

  alias Raycaster.{Engine, Keyboard, Screen}

  @report_ms 1000

  def start do
    {:ok, scene} = Screen.start()
    {:ok, _keyboard} = Keyboard.start_link()

    IO.puts("raycaster: #{Engine.cols()} columns, #{Screen.width()}x#{Screen.height()}")

    # Fetched once and passed around: AtomVM copies a module literal every time
    # it is used, so looking the map up per frame (or per ray step) is ruinous.
    grid = Engine.grid()

    presenter = spawn_link(fn -> present(scene) end)

    now = now()
    stats = %{at: now, frames: 0, ray: 0, wait: 0, hud: "", drawn: nil, showing: false}
    loop(presenter, grid, Engine.new(), [], now, stats)
  end

  defp loop(presenter, grid, player, held, last, stats) do
    {held, last} =
      case drain(held) do
        [] when player == stats.drawn -> idle(stats.at + @report_ms - now())
        held -> {held, last}
      end

    t0 = now()
    player = Engine.step(grid, player, held, t0 - last)

    items = Engine.frame(grid, player, Screen.width(), Screen.height())
    t1 = now()

    # One frame at a time goes to the display: wait for the last one if it is
    # still going out.
    shown(stats.showing)
    t2 = now()
    send(presenter, {:frame, self(), [hud(stats.hud) | items]})

    stats = %{
      stats
      | frames: stats.frames + 1,
        ray: stats.ray + t1 - t0,
        wait: stats.wait + t2 - t1,
        drawn: player,
        showing: true
    }

    loop(presenter, grid, player, held, t0, report(stats, t2, length(items)))
  end

  defp shown(false), do: :ok
  defp shown(true), do: receive(do: (:shown -> :ok))

  # avm_scene answers the call only once the display has taken the frame, so
  # :shown means the next one can be sent.
  defp present(scene) do
    receive do
      {:frame, from, items} ->
        :ok = GenServer.call(scene, {:frame, items}, 5_000)
        send(from, :shown)
        present(scene)
    end
  end

  # Nothing to draw until a key goes down, or until the line in the corner is
  # due. The clock restarts here, so the time spent waiting is not taken for
  # one long frame and the first step after it does not jump.
  defp idle(timeout) do
    receive do
      {:key, :down, label} -> {[label], now()}
    after
      max(timeout, 0) -> {[], now()}
    end
  end

  # Keys held right now: a press adds, a release removes.
  defp drain(held) do
    receive do
      {:key, :down, label} -> drain([label | :lists.delete(label, held)])
      {:key, :up, label} -> drain(:lists.delete(label, held))
    after
      0 -> held
    end
  end

  defp report(%{frames: frames} = stats, now, rects) when now - stats.at >= @report_ms do
    # Rounded, so that standing still (one frame in a little over a second)
    # reads 1 and not 0.
    elapsed = now - stats.at
    fps = div(frames * 1000 + div(elapsed, 2), elapsed)
    ray = div(stats.ray * 10, max(frames, 1))
    wait = div(stats.wait * 10, max(frames, 1))
    line = "#{fps} fps  ray #{tenths(ray)} ms  wait #{tenths(wait)} ms  #{rects} rects"

    IO.puts(line)
    %{stats | at: now, frames: 0, ray: 0, wait: 0, hud: line}
  end

  defp report(stats, _now, _rects), do: stats

  defp tenths(n), do: "#{div(n, 10)}.#{rem(n, 10)}"

  defp hud(text), do: {:text, 4, 4, :default16px, 0xFFFF00, 0x000000, text}

  defp now, do: :erlang.monotonic_time(:millisecond)
end
