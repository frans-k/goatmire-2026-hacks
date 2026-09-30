defmodule Raycaster.Omen do
  @moduledoc """
  The badge's four LEDs, telling you the goat is near before you see it.

  `level/2` turns where you and the goat are into a level of dread, through walls
  too, and a process of its own plays that level's pattern on a timer, so the game
  only sends it a message when the level changes:

    * 0: no goat, or more than seven cells off: dark
    * 1: within seven cells, a dark red ember crawls across the four
    * 2: within four, red, purple and orange shift round them
    * 3: within two, and it is after you: a red and white strobe
    * `:caught`: steady blood red, under the game over screen

  Every frame is encoded once when the process starts and only written after
  that. The colours are dim on purpose: four LEDs at full brightness hurt to look
  at, and draw a lot more current.
  """

  alias Raycaster.SK6812

  # Squared, in the map's fixed point (256 to a cell), so no square root is taken.
  @far 7 * 256 * (7 * 256)
  @near 4 * 256 * (4 * 256)
  @close 2 * 256 * (2 * 256)

  @doc "Starts the process, with the LEDs dark. Without LEDs it only listens."
  def start_link do
    spawn_link(fn ->
      spi = open()
      frames = {frames(1), frames(2), frames(3), frames(:caught)}
      show(spi, SK6812.encode(off()))
      loop(spi, frames, 0, [], :infinity)
    end)
  end

  @doc "Changes the pattern. Send it only when the level has changed."
  def set(omen, level), do: send(omen, {:level, level})

  @doc "How much to dread a goat, `{x, y, hunting}` or nil, from where the player stands."
  def level(_player, nil), do: 0

  def level(%{x: x, y: y}, {gx, gy, hunting}) do
    dx = gx - x
    dy = gy - y
    far = dx * dx + dy * dy

    cond do
      far <= @close and hunting -> 3
      far <= @near -> 2
      far <= @far -> 1
      true -> 0
    end
  end

  @doc "The pattern for a level: `{ms a frame, [four {r, g, b}, ...]}`."
  def pattern(0), do: {:infinity, [off()]}

  def pattern(1) do
    ember = {40, 0, 0}
    dark = {5, 0, 0}

    {500,
     [
       [ember, dark, dark, dark],
       [dark, ember, dark, dark],
       [dark, dark, ember, dark],
       [dark, dark, dark, ember]
     ]}
  end

  def pattern(2) do
    red = {56, 0, 0}
    purple = {24, 0, 36}
    orange = {48, 14, 0}
    bruise = {8, 0, 16}

    {250,
     [
       [red, purple, orange, bruise],
       [bruise, red, purple, orange],
       [orange, bruise, red, purple],
       [purple, orange, bruise, red]
     ]}
  end

  def pattern(3) do
    red = {64, 0, 0}
    white = {40, 40, 40}

    {100, [[red, white, red, white], [white, red, white, red]]}
  end

  def pattern(:caught), do: {:infinity, [[{64, 0, 0}, {64, 0, 0}, {64, 0, 0}, {64, 0, 0}]]}

  defp off, do: [{0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}]

  defp frames(level) do
    {ms, pixels} = pattern(level)
    {ms, :lists.map(&SK6812.encode/1, pixels)}
  end

  defp frames_for({one, _two, _three, _caught}, 1), do: one
  defp frames_for({_one, two, _three, _caught}, 2), do: two
  defp frames_for({_one, _two, three, _caught}, 3), do: three
  defp frames_for({_one, _two, _three, caught}, :caught), do: caught
  defp frames_for(_frames, _level), do: {:infinity, [SK6812.encode(off())]}

  # `left` is what is still to show of this level's frames before they go round.
  defp loop(spi, frames, level, left, wait) do
    receive do
      {:level, ^level} ->
        loop(spi, frames, level, left, wait)

      {:level, new} ->
        {ms, all} = frames_for(frames, new)
        next(spi, frames, new, all, all, ms)
    after
      wait ->
        {ms, all} = frames_for(frames, level)
        next(spi, frames, level, left, all, ms)
    end
  end

  defp next(spi, frames, level, [], all, ms), do: next(spi, frames, level, all, all, ms)

  defp next(spi, frames, level, [frame | rest], _all, ms) do
    show(spi, frame)
    loop(spi, frames, level, rest, ms)
  end

  defp open do
    SK6812.open()
  catch
    _kind, _reason -> nil
  end

  defp show(nil, _frame), do: :ok

  defp show(spi, frame) do
    SK6812.write(spi, frame)
  catch
    _kind, _reason -> :ok
  end
end
