defmodule Raycaster.Peers do
  @moduledoc """
  The other players a badge has heard from lately.

  Plain data, so the page can keep it in its state and the tests can run it on the
  host. A player not heard from for `@ttl_ms` is gone, whether or not it said
  goodbye: a badge that lost power says nothing. The table is capped, because
  anyone can publish to an open broker.
  """

  # A badge sends at least once a second while it is playing.
  @ttl_ms 4_000
  @max 12

  @type t :: [{binary, map, integer}]

  @spec new() :: t
  def new, do: []

  @doc "Records where `id` is, as heard at `now` (milliseconds)."
  @spec put(t, binary, map, integer) :: t
  def put(peers, id, pose, now) do
    peers = :lists.keystore(id, 1, peers, {id, pose, now})

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

  defp fresh([{_id, _pose, seen} = peer | rest], now, acc) when now - seen < @ttl_ms,
    do: fresh(rest, now, [peer | acc])

  defp fresh([_stale | rest], now, acc), do: fresh(rest, now, acc)

  @doc "What `Raycaster.Engine.sprites/5` takes."
  @spec others(t) :: [{integer, integer, integer}]
  def others([]), do: []

  def others([{_id, %{x: x, y: y, colour: colour}, _seen} | rest]),
    do: [{x, y, colour} | others(rest)]

  @spec count(t) :: non_neg_integer
  def count(peers), do: length(peers)
end
