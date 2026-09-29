defmodule Raycaster do
  @moduledoc """
  Walk around a small map with the badge keyboard.

  Arrows or W A S D move and turn, Q and E strafe. Once a second it prints
  frames per second and where the time went (casting rays, or waiting for the
  display), and shows the same on screen.
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

    now = now()
    loop(scene, grid, Engine.new(), [], now, %{at: now, frames: 0, ray: 0, push: 0, hud: ""})
  end

  defp loop(scene, grid, player, held, last, stats) do
    held = drain(held)

    t0 = now()
    player = Engine.step(grid, player, held, t0 - last)

    items = Engine.frame(grid, player, Screen.width(), Screen.height())
    t1 = now()

    :ok = GenServer.call(scene, {:frame, [hud(stats.hud) | items]}, 5_000)
    t2 = now()

    stats = %{
      stats
      | frames: stats.frames + 1,
        ray: stats.ray + t1 - t0,
        push: stats.push + t2 - t1
    }

    loop(scene, grid, player, held, t0, report(stats, t2, length(items)))
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
    fps = div(frames * 1000, now - stats.at)
    ray = div(stats.ray * 10, max(frames, 1))
    push = div(stats.push * 10, max(frames, 1))
    line = "#{fps} fps  ray #{tenths(ray)} ms  push #{tenths(push)} ms  #{rects} rects"

    IO.puts(line)
    %{at: now, frames: 0, ray: 0, push: 0, hud: line}
  end

  defp report(stats, _now, _rects), do: stats

  defp tenths(n), do: "#{div(n, 10)}.#{rem(n, 10)}"

  defp hud(text), do: {:text, 4, 4, :default16px, 0xFFFF00, 0x000000, text}

  defp now, do: :erlang.monotonic_time(:millisecond)
end
