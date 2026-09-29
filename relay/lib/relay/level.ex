defmodule Relay.Level do
  @moduledoc """
  The badges' map, for the goat: which cells are open, what can be seen from
  where, and the way from one cell to another.

  It is read from `priv/map.txt` while compiling, the same file the badge's
  engine is built from (`../raycaster/lib/engine.ex`), so the two cannot
  disagree. Positions are the badges' fixed point, 256 to a cell; a cell is
  `{column, row}`.
  """

  @path Path.expand("../../priv/map.txt", __DIR__)
  @external_resource @path

  @rows @path |> File.read!() |> String.split("\n", trim: true)
  @size length(@rows)

  @grid @rows
        |> Enum.flat_map(fn row ->
          row |> String.to_charlist() |> Enum.map(&if(&1 == ?., do: 0, else: &1 - ?0))
        end)
        |> List.to_tuple()

  @type cell :: {non_neg_integer, non_neg_integer}

  @doc "Cells across and down."
  def size, do: @size

  @doc "Whether the cell is floor. Outside the map is wall."
  @spec open_cell?(cell) :: boolean
  def open_cell?({cx, cy}) when cx >= 0 and cy >= 0 and cx < @size and cy < @size,
    do: elem(@grid, cy * @size + cx) == 0

  def open_cell?(_cell), do: false

  @doc "Whether the point is on floor."
  def open?(x, y), do: open_cell?(cell(x, y))

  @doc "The cell a point is in."
  @spec cell(number, number) :: cell
  def cell(x, y), do: {floor_div(x), floor_div(y)}

  @doc "The middle of a cell."
  def centre({cx, cy}), do: {cx * 256 + 128, cy * 256 + 128}

  @doc "Every open cell."
  def open_cells,
    do: for(cy <- 0..(@size - 1), cx <- 0..(@size - 1), open_cell?({cx, cy}), do: {cx, cy})

  @doc """
  Nothing solid between two points, looked at every quarter cell: the same walk
  the badge makes to decide whether a figure is hidden, so the goat sees you
  when you would see it.
  """
  def visible?(x0, y0, x1, y1) do
    dx = x1 - x0
    dy = y1 - y0
    steps = max(trunc(max(abs(dx), abs(dy)) / 64), 1)

    Enum.all?(1..steps//1, fn i ->
      i == steps or open?(x0 + dx * i / steps, y0 + dy * i / steps)
    end)
  end

  @doc """
  The next cell on a shortest way from `from` to `to`, moving across cell sides
  only, or nil when `from` is `to` or there is no way.
  """
  @spec next_cell(cell, cell) :: cell | nil
  def next_cell(from, to) when from == to, do: nil

  def next_cell(from, to) do
    # Searched from the goal, so the first step is the neighbour of `from` that
    # is nearest to it.
    distances = distances(to)

    case Map.get(distances, from) do
      nil ->
        nil

      _reachable ->
        from
        |> neighbours()
        |> Enum.filter(&Map.has_key?(distances, &1))
        |> Enum.min_by(&Map.fetch!(distances, &1), fn -> nil end)
    end
  end

  @doc "The open cell farthest from `from` by walking, the nearer-to-the-top-left of a tie."
  @spec farthest_from(cell) :: cell
  def farthest_from(from) do
    from
    |> distances()
    |> Enum.max_by(fn {{cx, cy}, steps} -> {steps, -cy, -cx} end)
    |> elem(0)
  end

  @doc "Steps from `from` to every cell that can be walked to."
  @spec distances(cell) :: %{cell => non_neg_integer}
  def distances(from), do: bfs(:queue.from_list([from]), %{from => 0})

  defp bfs(queue, seen) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        seen

      {{:value, cell}, queue} ->
        steps = Map.fetch!(seen, cell) + 1
        new = Enum.reject(neighbours(cell), &Map.has_key?(seen, &1))

        bfs(
          Enum.reduce(new, queue, &:queue.in/2),
          Enum.reduce(new, seen, &Map.put(&2, &1, steps))
        )
    end
  end

  defp neighbours({cx, cy}),
    do: Enum.filter([{cx + 1, cy}, {cx - 1, cy}, {cx, cy + 1}, {cx, cy - 1}], &open_cell?/1)

  defp floor_div(n) when is_integer(n), do: Integer.floor_div(n, 256)
  defp floor_div(n), do: floor(n / 256)
end
