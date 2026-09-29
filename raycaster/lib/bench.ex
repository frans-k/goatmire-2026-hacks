defmodule Raycaster.Bench do
  @moduledoc """
  Where does the time go on the badge? Set `start: Raycaster.Bench` in mix.exs,
  flash, and read the monitor.

  It times a handful of tiny loops, each on its own, so the cost of one
  operation can be read off. The interesting pair is a 256 entry table read as
  a module literal against the same table passed as an argument: AtomVM copies
  a literal onto the heap on every use, which the literal loops pay for.
  """

  import Bitwise

  # A 256 entry tuple like the raycaster's map and sine table.
  @table List.to_tuple(Enum.to_list(0..255))

  @n 5_000
  # The literal loops get few iterations: at 5000 they ran the badge out of
  # memory (OOM while reading literals_table).
  @n_literal 100

  def start do
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
