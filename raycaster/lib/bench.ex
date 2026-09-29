defmodule Raycaster.Bench do
  @moduledoc """
  Where does the time go on the badge? Set `start: Raycaster.Bench` in mix.exs,
  flash, and read the monitor.

  First it renders a fixed tour of views, the same ones every time, so a change
  to the engine can be compared frame for frame instead of against a walk
  around the map, which varies too much (61 to 111 ms a frame).

  Then it times a handful of tiny loops, each on its own, so the cost of one
  operation can be read off. The interesting pair is a 256 entry table read as
  a module literal against the same table passed as an argument: AtomVM copies
  a literal onto the heap on every use, which the literal loops pay for.
  """

  import Bitwise

  alias Raycaster.{Engine, Screen}

  # Places to stand, in Q8 (256 is one cell), and angles, 65536 to a turn. The
  # spawn point looking down the long corridor, rays running exactly along an
  # axis, a wall right in front, and views across the open rooms. The engine
  # tests check these frames against test/tour_frames.exs.
  @tour [
    {384, 384, 0},
    {384, 384, 16_384},
    {384, 384, 8_192},
    {2000, 1500, 40_000},
    {3200, 3200, 32_768},
    {1900, 700, 50_000},
    {800, 2400, 12_000},
    {3500, 600, 24_000}
  ]

  # Each view is drawn this many times and the average kept.
  @frames 5

  # A 256 entry tuple like the raycaster's map and sine table.
  @table List.to_tuple(Enum.to_list(0..255))

  @n 5_000
  # The literal loops get few iterations: at 5000 they ran the badge out of
  # memory (OOM while reading literals_table).
  @n_literal 100

  def tour, do: for({x, y, a} <- @tour, do: %{x: x, y: y, a: a})

  def start do
    frames()
    micro()
  end

  defp frames do
    grid = Engine.grid()

    views = tour()

    total =
      Enum.reduce(views, 0, fn player, total ->
        ms = timed(fn -> draw(grid, player, @frames) end)
        IO.puts("view #{player.x},#{player.y} angle #{player.a}: #{tenths(ms, @frames)} ms")
        total + ms
      end)

    IO.puts("tour: #{tenths(total, @frames * length(views))} ms a frame")
  end

  defp draw(_grid, _player, 0), do: :ok

  defp draw(grid, player, n) do
    Engine.frame(grid, player, Screen.width(), Screen.height())
    draw(grid, player, n - 1)
  end

  defp micro do
    table = @table

    results = [
      {"empty loop", @n, timed(fn -> empty(@n) end)},
      {"table as literal", @n_literal, timed(fn -> literal(@n_literal, 0) end)},
      {"table as argument", @n, timed(fn -> argument(@n, table, 0) end)},
      {"arithmetic", @n, timed(fn -> arithmetic(@n, 0) end)},
      {"9 argument call", @n, timed(fn -> call(@n, 0) end)}
    ]

    for {label, n, ms} <- results do
      IO.puts("#{label}: #{ms} ms for #{n}, #{div(ms * 1000, n)} us each")
    end
  end

  # total / n, to one decimal.
  defp tenths(total, n) do
    t = div(total * 10, n)
    "#{div(t, 10)}.#{rem(t, 10)}"
  end

  defp timed(fun) do
    t0 = :erlang.monotonic_time(:millisecond)
    fun.()
    :erlang.monotonic_time(:millisecond) - t0
  end

  defp empty(0), do: :ok
  defp empty(n), do: empty(n - 1)

  defp literal(0, acc), do: acc
  defp literal(n, acc), do: literal(n - 1, acc + elem(@table, n &&& 255))

  defp argument(0, _table, acc), do: acc
  defp argument(n, table, acc), do: argument(n - 1, table, acc + elem(table, n &&& 255))

  defp arithmetic(0, acc), do: acc

  defp arithmetic(n, acc),
    do: arithmetic(n - 1, acc + div(n * 256, 79) + (n >>> 3) - abs(n - 100))

  defp call(0, acc), do: acc
  defp call(n, acc), do: call(n - 1, nine(acc, 2, 3, 4, 5, 6, 7, 8, 9))

  defp nine(a, _b, _c, _d, _e, _f, _g, _h, _i), do: a + 1
end
