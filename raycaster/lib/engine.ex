defmodule Raycaster.Engine do
  @moduledoc """
  A small Wolfenstein-style raycaster, in integers only.

  AtomVM has no fast floats on this chip, so positions are Q8 fixed point (256
  is one map cell), angles are 65536 to a turn, and sine comes from a table
  built while compiling on the laptop. `frame/4` turns a player into a display
  list of rectangles, one per run of equal wall columns.

  The map is not read from this module while rendering: see `grid/0`.
  """

  import Bitwise

  # Vertical slices across the screen. Ray casting is nearly all of the frame
  # time and costs the same per slice, so this is the frame rate knob: 80 slices
  # ran at 7 fps on the badge standing still, 40 at 12-13 (about 10 while
  # walking). It must divide the screen width.
  @cols 40
  # Distance along a ray that never crosses a grid line. AtomVM's integers are
  # 28 bits wide on this chip before they spill onto the heap, so keep it
  # below 2^27.
  @far 1 <<< 26

  # 16 x 16. Digits are wall types, `.` is floor. The outer ring must be wall:
  # rays are not bounds checked and stop only when they enter a wall cell.
  @rows [
    "3333333333333333",
    "3..............3",
    "3..1111....22..3",
    "3..1..........23",
    "3..1..........23",
    "3..1......11...3",
    "3.......2..1...3",
    "3.......2..1...3",
    "3..22...2......3",
    "3..............3",
    "3....1111......3",
    "3....1..1..22..3",
    "3....1..1..2...3",
    "3...........2..3",
    "3..............3",
    "3333333333333333"
  ]

  @size length(@rows)

  # One flat tuple, row after row. AtomVM copies a module literal onto the heap
  # every time it is used, and this one is 256 words: looked up per grid step
  # that ran the badge out of memory. So it is fetched once with grid/0 and
  # handed down as an argument, which passes a pointer instead.
  @grid @rows
        |> Enum.flat_map(fn row ->
          row
          |> String.to_charlist()
          |> Enum.map(fn
            ?. -> 0
            char -> char - ?0
          end)
        end)
        |> List.to_tuple()

  @ceiling 0x202838
  @floor 0x504030

  # Q8 per second, and angle units per second.
  @move_speed 800
  @turn_speed 40_000
  # How close to a wall the player may get, in Q8.
  @radius 60

  def new, do: %{x: 384, y: 384, a: 0}

  # The map. Call this once and pass the result to step/4 and frame/4.
  def grid, do: @grid

  def cols, do: @cols

  # Held keys are labels from Raycaster.Keymap.
  def step(grid, state, held, dt_ms) do
    forward = axis(held, ["Up", "W"], ["Down", "S"])
    strafe = axis(held, ["E"], ["Q"])
    turn = axis(held, ["Right", "D"], ["Left", "A"])

    angle = state.a + div(turn * @turn_speed * dt_ms, 1000)
    index = index(angle)
    dir_x = cos(index)
    dir_y = sin(index)

    distance = div(@move_speed * dt_ms, 1000)
    dx = div((dir_x * forward - dir_y * strafe) * distance, 256)
    dy = div((dir_y * forward + dir_x * strafe) * distance, 256)

    # Each axis on its own, so a wall is slid along instead of stopping dead.
    x =
      if open?(grid, state.x + dx + sign(dx) * @radius, state.y), do: state.x + dx, else: state.x

    y = if open?(grid, x, state.y + dy + sign(dy) * @radius), do: state.y + dy, else: state.y

    %{state | x: x, y: y, a: angle}
  end

  def frame(grid, %{x: x, y: y, a: angle}, width, height) do
    index = index(angle)
    dir_x = cos(index)
    dir_y = sin(index)
    # The camera plane is perpendicular to the direction, 0.66 as long: about a
    # 66 degree field of view.
    plane_x = div(-dir_y * 169, 256)
    plane_y = div(dir_x * 169, 256)
    column_width = div(width, @cols)

    # The first item is on top, so floor and ceiling go last, behind the walls.
    # The walls are put in front of them as they are found.
    behind = [
      {:rect, 0, div(height, 2), width, height - div(height, 2), @floor},
      {:rect, 0, 0, width, div(height, 2), @ceiling}
    ]

    columns(grid, 0, x, y, dir_x, dir_y, plane_x, plane_y, column_width, height, nil, behind)
  end

  # `run` is the rectangle being widened: neighbouring columns with the same
  # height and colour (a flat wall facing you) become one rectangle.
  defp columns(_grid, @cols, _x, _y, _dx, _dy, _px, _py, _w, _h, run, acc), do: emit(run, acc)

  defp columns(grid, i, x, y, dir_x, dir_y, plane_x, plane_y, column_width, height, run, acc) do
    camera = div(2 * i * 256, @cols) - 256
    ray_x = dir_x + div(plane_x * camera, 256)
    ray_y = dir_y + div(plane_y * camera, 256)

    {wall, side, dist} = cast(grid, x, y, ray_x, ray_y)
    line = min(div(height * 256, max(dist, 1)), height)
    top = div(height - line, 2)
    colour = colour(wall, side, dist)

    {run, acc} =
      case run do
        {rx, rw, ^top, ^line, ^colour} -> {{rx, rw + column_width, top, line, colour}, acc}
        _ -> {{i * column_width, column_width, top, line, colour}, emit(run, acc)}
      end

    columns(grid, i + 1, x, y, dir_x, dir_y, plane_x, plane_y, column_width, height, run, acc)
  end

  defp emit(nil, acc), do: acc
  defp emit({x, w, y, h, colour}, acc), do: [{:rect, x, y, w, h, colour} | acc]

  # Digital differential analysis: hop from grid line to grid line along the
  # ray until a wall cell is entered. Returns {wall type, side hit, distance}.
  defp cast(grid, x, y, ray_x, ray_y) do
    map_x = x >>> 8
    map_y = y >>> 8

    {delta_x, step_x, side_x} = axis_setup(x, map_x, ray_x)
    {delta_y, step_y, side_y} = axis_setup(y, map_y, ray_y)

    # The cell is tracked as its place in the grid tuple, so a step across a
    # vertical grid line is +-1 and across a horizontal one +-@size. Counted
    # from 1, as :erlang.element/2 does: elem/2 counts from 0 and adds the 1 on
    # every read.
    cell = map_y * @size + map_x + 1
    march(grid, cell, side_x, side_y, delta_x, delta_y, step_x, step_y * @size)
  end

  defp axis_setup(_pos, _cell, 0), do: {@far, 1, @far}

  defp axis_setup(pos, cell, ray) do
    delta = div(65_536, abs(ray))

    # How far along the ray the first grid line is: the rest of the cell, as a
    # fraction of a whole cell, times the length of a whole cell.
    if ray < 0 do
      {delta, -1, div((pos - (cell <<< 8)) * delta, 256)}
    else
      {delta, 1, div((((cell + 1) <<< 8) - pos) * delta, 256)}
    end
  end

  # The inner loop, run for every grid line every ray crosses: nearly all of
  # the frame time. Kept to a comparison, two additions and a tuple read per
  # step: 6 BEAM instructions, where it was about 37 with the bounds checked
  # cell/3 call and a step counter. There is no bounds check and no step limit, because the map's outer
  # wall stops every ray.
  defp march(grid, cell, side_x, side_y, delta_x, delta_y, step_x, step_y) do
    if side_x < side_y do
      cell = cell + step_x

      case :erlang.element(cell, grid) do
        0 -> march(grid, cell, side_x + delta_x, side_y, delta_x, delta_y, step_x, step_y)
        wall -> {wall, 0, side_x}
      end
    else
      cell = cell + step_y

      case :erlang.element(cell, grid) do
        0 -> march(grid, cell, side_x, side_y + delta_y, delta_x, delta_y, step_x, step_y)
        wall -> {wall, 1, side_y}
      end
    end
  end

  defp cell(_grid, x, y) when x < 0 or y < 0 or x >= @size or y >= @size, do: 1
  defp cell(grid, x, y), do: elem(grid, y * @size + x)

  defp open?(grid, x, y), do: cell(grid, x >>> 8, y >>> 8) == 0

  # Darker with distance, and walls facing along y a little darker again, so
  # corners read.
  defp colour(wall, side, dist) do
    rgb = rgb(wall)
    r = rgb >>> 16
    g = rgb >>> 8 &&& 255
    b = rgb &&& 255
    shade = max(48, 256 - div(dist, 12))
    shade = if side == 1, do: div(shade * 3, 4), else: shade

    div(r * shade, 256) <<< 16 ||| div(g * shade, 256) <<< 8 ||| div(b * shade, 256)
  end

  defp axis(held, plus, minus) do
    if(Enum.any?(plus, &(&1 in held)), do: 1, else: 0) -
      if(Enum.any?(minus, &(&1 in held)), do: 1, else: 0)
  end

  defp sign(n) when n > 0, do: 1
  defp sign(n) when n < 0, do: -1
  defp sign(_n), do: 0

  # Wall colours by type. A function of plain integers rather than a tuple of
  # tuples, because AtomVM copies a module literal onto the heap on every use,
  # and this is read once per column.
  defp rgb(1), do: 0xC83C32
  defp rgb(2), do: 0x3CAA46
  defp rgb(3), do: 0x4664D2

  defp index(angle), do: angle >>> 8 &&& 255
  defp sin(index), do: sin_table(index)
  defp cos(index), do: sin_table(index + 64 &&& 255)

  # 256 steps to a turn, scaled by 256. One clause per step, built while
  # compiling, for the same reason as rgb/1: the compiler turns them into a
  # jump table of plain integers, where a tuple would be a literal.
  for step <- 0..255 do
    defp sin_table(unquote(step)),
      do: unquote(round(:math.sin(step * 2 * :math.pi() / 256) * 256))
  end
end
