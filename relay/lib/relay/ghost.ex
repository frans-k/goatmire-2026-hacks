defmodule Relay.Ghost do
  @moduledoc """
  A player that is not a badge: it wanders the map and is hunted by the goat like one.

  So that someone trying the game, a reviewer say, finds others in the room and a goat that
  has something to do. It is in a room through `Relay.Hub` like a badge, but with `ghost: true`,
  so the dashboard's counts of who is playing leave it out, and it never calls
  `Relay.Stats.seen/1`, so it is not a badge that played.

  It takes a step a second, in a straight line that now and then turns, and a new way when
  it meets a wall. When the goat catches it, it comes back at the start two seconds later,
  as a badge does when a key is pressed, but somewhere open and well away from the goat, which it
  knows from the snapshots every player is sent: at the start, where the goat tends to be, it
  would be caught over and over. If the hub restarts, it joins again.
  """

  use GenServer

  alias Relay.Hub
  alias Relay.Level

  # The map's fixed point is 256 to a cell, and a step is half a cell.
  @step 128
  # How far from its middle a ghost may not be in a wall, as a badge's body is wide.
  @body 60
  # The goat is not to be this close, in the map's fixed point, where a ghost is put.
  @away 6 * 256

  def start_link(n), do: GenServer.start_link(__MODULE__, n)

  @impl true
  def init(n) do
    send(self(), :join)
    {:ok, %{n: n, x: 0, y: 0, angle: 0, out: false, goat: nil}}
  end

  @impl true
  def handle_info(:join, state) do
    case Hub.join(self(), ghost: true) do
      {:error, _reason} ->
        Process.send_after(self(), :join, 5_000)
        {:noreply, state}

      _joined ->
        {x, y} = place(state.goat)
        Process.monitor(Hub)
        Process.send_after(self(), :step, 300)
        {:noreply, %{state | x: x, y: y, angle: turn(), out: false}}
    end
  end

  def handle_info(:step, %{out: true} = state) do
    Process.send_after(self(), :step, 1_000)
    {:noreply, state}
  end

  def handle_info(:step, state) do
    Process.send_after(self(), :step, 1_000)
    state = state |> walk() |> wander()
    Hub.move(self(), state.x, state.y)
    {:noreply, state}
  end

  def handle_info({:caught, _frame}, state) do
    Process.send_after(self(), :respawn, 2_000)
    {:noreply, %{state | out: true}}
  end

  def handle_info(:respawn, state) do
    {x, y} = place(state.goat)
    Hub.respawn(self())
    {:noreply, %{state | out: false, x: x, y: y}}
  end

  # The hub went down and came back without this player in it.
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Process.send_after(self(), :join, 1_000)
    {:noreply, %{state | out: true}}
  end

  # A ghost draws nothing, and only keeps where the goat is.
  def handle_info({:snap, frame}, state) do
    case JSON.decode!(frame) do
      [_, _, _, "snap", %{"g" => [x, y, _hunting]}] -> {:noreply, %{state | goat: {x, y}}}
      _no_goat -> {:noreply, %{state | goat: nil}}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp walk(state) do
    radians = state.angle * 2 * :math.pi() / 65_536
    x = state.x + round(:math.cos(radians) * @step)
    y = state.y + round(:math.sin(radians) * @step)

    if clear?(x, y), do: %{state | x: x, y: y}, else: %{state | angle: turn()}
  end

  defp wander(state) do
    if :rand.uniform(4) == 1 do
      %{state | angle: rem(state.angle + :rand.uniform(9_000) - 4_500 + 65_536, 65_536)}
    else
      state
    end
  end

  defp clear?(x, y), do: Level.open?(x + @body, y + @body) and Level.open?(x - @body, y - @body)

  defp turn, do: :rand.uniform(65_535)

  @doc false
  # An open spot at least `@away` from the goat, `{x, y}` or nil.
  def place(goat) do
    spots = Stream.repeatedly(fn -> {:rand.uniform(4095), :rand.uniform(4095)} end)
    open = Stream.filter(spots, fn {x, y} -> Level.open?(x, y) end)

    open |> Stream.filter(&far?(&1, goat)) |> Enum.take(1) |> hd()
  end

  defp far?(_spot, nil), do: true

  defp far?({x, y}, {gx, gy}) do
    (x - gx) * (x - gx) + (y - gy) * (y - gy) >= @away * @away
  end
end
