defmodule Relay.GhostTest do
  # One hub for the whole app, so these cannot run side by side.
  use ExUnit.Case, async: false

  alias Relay.Hub

  setup do
    on_exit(fn -> wait_until(fn -> Hub.counts() == [] end) end)
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never became true")
      true -> Process.sleep(20) && wait_until(fun, tries - 1)
    end
  end

  defp positions do
    assert_receive {:snap, frame}, 1_000
    [nil, nil, _topic, "snap", %{"p" => players}] = JSON.decode!(frame)
    players
  end

  test "a ghost is in a room, and the count of who is playing leaves it out" do
    ghost = start_supervised!({Relay.Ghost, 1})
    wait_until(fn -> Hub.ghost_count() == 1 end)

    assert [{_room, 1}] = Hub.counts()
    assert Process.alive?(ghost)

    stop_supervised!(Relay.Ghost)
    wait_until(fn -> Hub.ghost_count() == 0 end)
    assert Hub.counts() == []
  end

  # A player is in the snapshot once it has said where it stands, which a ghost does a
  # moment after it joins.
  defp ghost_at do
    case positions() do
      [[_slot, x, y]] -> {x, y}
      _none_yet -> ghost_at()
    end
  end

  test "a badge in the room sees the ghost, and sees it move" do
    start_supervised!({Relay.Ghost, 1})
    wait_until(fn -> Hub.ghost_count() == 1 end)
    {_room, _slot, _max} = Hub.join(self())

    first = ghost_at()
    # It takes a step a second, and the hub ticks every 50 ms here.
    assert wait_for_change(first, System.monotonic_time(:millisecond) + 4_000)
  end

  defp wait_for_change(first, deadline) do
    cond do
      ghost_at() != first -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> wait_for_change(first, deadline)
    end
  end

  test "a ghost that was caught is out for a while, and then back" do
    ghost = start_supervised!({Relay.Ghost, 1})
    wait_until(fn -> Hub.ghost_count() == 1 end)

    send(ghost, {:caught, "frame"})
    assert %{out: true} = :sys.get_state(ghost)

    wait_until(fn -> :sys.get_state(ghost).out == false end, 150)
    assert %{x: 384, y: 384} = :sys.get_state(ghost)
  end

  test "ghosts started by Relay.Ghosts are as many as asked for, none for none" do
    start_supervised!({Relay.Ghosts, 3})
    wait_until(fn -> Hub.ghost_count() == 3 end)
    stop_supervised!(Relay.Ghosts)
    wait_until(fn -> Hub.ghost_count() == 0 end)

    start_supervised!({Relay.Ghosts, 0})
    assert Hub.ghost_count() == 0
  end
end
