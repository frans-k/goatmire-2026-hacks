defmodule Relay.Goat do
  @moduledoc """
  The evil goat: one to a room, moved by the server, drawn by the badges.
  Plain data, no processes; `Relay.Rooms` keeps one per room and `Relay.Hub`
  steps it.

  It wanders from one random open cell to another until it sees a player, then
  hunts them: straight at them while they are in sight, faster than it wanders
  but slower than a badge walks (800), so running away works. It has three paces:
  `:calm`, to start with, then `:fast` and `:faster`, which the room asks for as
  someone in it lasts longer (see `Relay.Rooms.pace/2`). When it loses
  sight of them it goes to where it last saw them and searches there for a few
  seconds before wandering again. Nearer than half a cell to a player is a catch.

  It sees through open floor only, with the walk the badge uses to hide
  figures, so it sees you exactly when you would see it. Positions are the
  badges' fixed point, 256 to a cell, kept as floats here and rounded for the
  wire. Players are what the badges last said, which can be a second old.
  """

  alias Relay.Level

  # Wandering and hunting, in the badges' fixed point per second, by pace.
  @calm {250, 330}
  @fast {350, 450}
  @faster {400, 520}
  # How far it sees: eight cells.
  @sight 2_048
  @reach 128
  @search_ms 4_000

  @type mode :: :wander | :hunt | :search
  @type t :: %{
          x: float,
          y: float,
          mode: mode,
          target: term,
          goal: {number, number} | nil,
          lost_at: integer | nil,
          rand: :rand.state()
        }

  @doc "A goat in the middle of `cell`, wandering. The seed makes its wandering repeatable."
  @spec new(Level.cell(), integer) :: t
  def new(cell, seed) do
    {x, y} = Level.centre(cell)

    %{
      x: x * 1.0,
      y: y * 1.0,
      mode: :wander,
      target: nil,
      goal: nil,
      lost_at: nil,
      rand: :rand.seed_s(:exsss, seed)
    }
  end

  @doc "Where it stands, in whole numbers, and whether it is after someone."
  @spec where(t) :: {integer, integer, boolean}
  def where(goat), do: {round(goat.x), round(goat.y), goat.mode != :wander}

  @doc """
  Moves the goat on by `dt_ms` at `now`, at `pace` (`:calm`, `:fast` or `:faster`). `players`
  is `[{id, x, y}]`, everyone it may hunt. Returns the goat and the ids of those it
  has caught.
  """
  @spec step(t, [{term, number, number}], non_neg_integer, integer, :calm | :fast | :faster) ::
          {t, [term]}
  def step(goat, players, dt_ms, now, pace \\ :calm) do
    {wander, hunt} = speeds(pace)
    goat = goat |> look(players, now) |> move(dt_ms, wander, hunt)
    {goat, for({id, x, y} <- players, distance(goat, x, y) < @reach, do: id)}
  end

  # Decides what it is doing: keeps after whoever it hunts while it sees them,
  # else goes after the nearest it sees, else searches where it lost them.
  defp look(goat, players, now) do
    seen =
      players
      |> Enum.filter(fn {_id, x, y} ->
        distance(goat, x, y) <= @sight and Level.visible?(goat.x, goat.y, x, y)
      end)
      |> Enum.sort_by(fn {_id, x, y} -> distance(goat, x, y) end)

    target = Enum.find(seen, fn {id, _x, _y} -> goat.mode == :hunt and id == goat.target end)

    case {target || List.first(seen), goat.mode} do
      {{id, x, y}, _mode} ->
        %{goat | mode: :hunt, target: id, goal: {x, y}, lost_at: nil}

      {nil, :hunt} ->
        %{goat | mode: :search, target: nil, lost_at: now}

      {nil, :search} when now - goat.lost_at >= @search_ms ->
        %{goat | mode: :wander, goal: nil, lost_at: nil}

      {nil, _mode} ->
        goat
    end
  end

  defp move(%{mode: :hunt} = goat, dt_ms, _wander, hunt) do
    {gx, gy} = goat.goal
    step = hunt * dt_ms / 1000
    {x, y} = towards(goat.x, goat.y, gx, gy, step)

    # Straight at them, unless that clips a corner: then round it.
    if Level.open?(x, y),
      do: %{goat | x: x, y: y},
      else: route(goat, goat.goal, step)
  end

  defp move(%{mode: :search} = goat, dt_ms, _wander, hunt),
    do: route(goat, goat.goal, hunt * dt_ms / 1000)

  defp move(%{mode: :wander} = goat, dt_ms, wander, _hunt) do
    goat = if arrived?(goat), do: wander_to(goat), else: goat
    route(goat, goat.goal, wander * dt_ms / 1000)
  end

  defp speeds(:faster), do: @faster
  defp speeds(:fast), do: @fast
  defp speeds(_calm), do: @calm

  defp arrived?(%{goal: nil}), do: true
  defp arrived?(%{goal: {gx, gy}} = goat), do: distance(goat, gx, gy) < 1

  defp wander_to(goat) do
    cells = Level.open_cells()
    {i, rand} = :rand.uniform_s(length(cells), goat.rand)
    %{goat | goal: Level.centre(Enum.at(cells, i - 1)), rand: rand}
  end

  # Along the shortest way through the cells, a cell's middle at a time; in the
  # goal's own cell, straight to it. Moving between the middles of neighbouring
  # open cells never touches a wall.
  defp route(goat, {gx, gy}, step) do
    here = Level.cell(goat.x, goat.y)

    {tx, ty} =
      case Level.next_cell(here, Level.cell(gx, gy)) do
        nil -> {gx, gy}
        next -> Level.centre(next)
      end

    {x, y} = towards(goat.x, goat.y, tx, ty, step)
    if Level.open?(x, y), do: %{goat | x: x, y: y}, else: goat
  end

  defp towards(x, y, tx, ty, step) do
    dx = tx - x
    dy = ty - y
    length = :math.sqrt(dx * dx + dy * dy)

    if length <= step,
      do: {tx * 1.0, ty * 1.0},
      else: {x + dx * step / length, y + dy * step / length}
  end

  defp distance(goat, x, y), do: :math.sqrt((goat.x - x) ** 2 + (goat.y - y) ** 2)
end
