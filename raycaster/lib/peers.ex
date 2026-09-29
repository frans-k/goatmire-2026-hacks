defmodule Raycaster.Peers do
  @moduledoc """
  The other players a badge has heard from lately.

  Plain data, so the page can keep it in its state and the tests can run it on the
  host. A player not heard from for `@ttl_ms` is gone, whether or not it said
  goodbye: a badge that lost power says nothing. The table is capped, because
  anyone can publish to an open broker.
  """

  # A badge sends at least every second and a half while it is playing.
  @ttl_ms 4_000
  @max 12

  # Between updates a player is drawn where it would be by now, going on as it was
  # going, for at most this long. Updates are only about twice a second, since
  # every one costs a badge about ten milliseconds to take in.
  @extrapolate_ms 600

  # Positions further apart in time than this say nothing about speed: the player
  # stood still for a while, and then moved.
  @speed_gap_ms 900

  @type t :: [{binary, map, integer, map | nil, integer | nil}]

  @spec new() :: t
  def new, do: []

  @doc "Records where `id` is, as heard at `now` (milliseconds)."
  @spec put(t, binary, map, integer) :: t
  def put(peers, id, pose, now) do
    entry =
      case :lists.keyfind(id, 1, peers) do
        {^id, before, seen, _older, _older_seen} -> {id, pose, now, before, seen}
        false -> {id, pose, now, nil, nil}
      end

    peers = :lists.keystore(id, 1, peers, entry)

    case length(peers) > @max do
      true -> :lists.sublist(:lists.reverse(:lists.keysort(3, peers)), @max)
      false -> peers
    end
  end

  @spec drop(t, binary) :: t
  def drop(peers, id), do: :lists.keydelete(id, 1, peers)

  @doc "Forgets everyone not heard from lately. Returns the same list if nobody is."
  @spec expire(t, integer) :: t
  def expire(peers, now) do
    case fresh(peers, now, []) do
      kept when length(kept) == length(peers) -> peers
      kept -> :lists.reverse(kept)
    end
  end

  defp fresh([], _now, acc), do: acc

  defp fresh([{_id, _pose, seen, _before, _before_seen} = peer | rest], now, acc)
       when now - seen < @ttl_ms,
       do: fresh(rest, now, [peer | acc])

  defp fresh([_stale | rest], now, acc), do: fresh(rest, now, acc)

  @doc """
  What `Raycaster.Engine.sprites/5` takes, as of `now`: each player where it would
  be by now if it kept going as it was between its last two updates.
  """
  @spec others(t, integer) :: [{integer, integer, integer}]
  def others([], _now), do: []

  def others([{_id, pose, seen, before, before_seen} | rest], now) do
    {x, y} = place(pose, seen, before, before_seen, now)
    [{x, y, pose.colour} | others(rest, now)]
  end

  @doc "Whether anyone is being drawn on the move, so the view needs redrawing."
  @spec moving?(t, integer) :: boolean
  def moving?([], _now), do: false

  def moving?([{_id, pose, seen, before, before_seen} | rest], now) do
    case velocity(pose, seen, before, before_seen) do
      {0, 0, _gap} -> moving?(rest, now)
      nil -> moving?(rest, now)
      {_dx, _dy, _gap} -> now - seen < @extrapolate_ms or moving?(rest, now)
    end
  end

  defp place(pose, seen, before, before_seen, now) do
    case velocity(pose, seen, before, before_seen) do
      {dx, dy, gap} ->
        elapsed = min(now - seen, @extrapolate_ms)
        {clamp(pose.x + div(dx * elapsed, gap)), clamp(pose.y + div(dy * elapsed, gap))}

      nil ->
        {pose.x, pose.y}
    end
  end

  # How far it moved over how long, between its last two updates.
  defp velocity(_pose, _seen, nil, _before_seen), do: nil

  defp velocity(pose, seen, before, before_seen) do
    gap = seen - before_seen

    if gap >= 50 and gap <= @speed_gap_ms do
      {pose.x - before.x, pose.y - before.y, gap}
    else
      nil
    end
  end

  # Stays on the map, whatever the extrapolation says.
  defp clamp(value), do: max(0, min(value, 4_095))

  @spec count(t) :: non_neg_integer
  def count(peers), do: length(peers)
end
