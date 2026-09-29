defmodule Raycaster.RelayWire do
  @moduledoc """
  What a badge says to the relay server (see `relay/`) and what it says back, in
  Phoenix channel frames, `[join_ref, ref, topic, event, payload]` as JSON.

    * to join: `phx_join` on `raycaster:lobby`; the answer says which room and slot
    * to say where it stands: `pos`, `{"x": .., "y": ..}`; no answer
    * every tick the server sends `snap`, `{"p": [[slot, x, y], ...]}`: everyone in
      the room, this badge too, by slot
    * `heartbeat` on `phoenix` now and then, or Phoenix drops a quiet connection

  Pure: `Raycaster.RelayLink` owns the socket. Nothing here trusts the server more
  than it needs to: a snapshot with anything odd in it is refused whole.
  """

  @topic "raycaster:lobby"
  @path "/badge/socket/websocket"

  # The map is 16 by 16 cells, 256 to a cell.
  @limit 4_096

  # More than a room holds is not a snapshot of a room.
  @room_max 16

  # Bright enough to read against the walls, one to a slot.
  @colours {0xE0433A, 0x3AA0E0, 0x3AE07A, 0xE0C93A, 0xB03AE0, 0xE07A3A, 0x3AE0D4, 0xE03A9A}

  @doc "The colour a slot is drawn in."
  @spec colour(pos_integer) :: non_neg_integer
  def colour(slot), do: elem(@colours, rem(slot - 1, tuple_size(@colours)))

  @doc "Where to connect: a base like `ws://192.168.1.5:4040`, and this badge's chip id."
  @spec url(binary, binary) :: binary
  def url(base, chip), do: trim(base) <> @path <> "?vsn=2.0.0&chip=" <> chip <> "&name=raycaster"

  @spec join(binary) :: binary
  def join(ref), do: frame(ref, ref, @topic, "phx_join", %{})

  @spec pos(binary, binary, integer, integer) :: binary
  def pos(join_ref, ref, x, y), do: frame(join_ref, ref, @topic, "pos", %{"x" => x, "y" => y})

  @spec heartbeat() :: binary
  def heartbeat, do: frame(nil, "0", "phoenix", "heartbeat", %{})

  @doc """
  Reads a frame from the server, given this badge's own slot (or nil before it has
  one): `{:joined, room, slot, max}`, `{:players, [{slot, x, y}]}` without this
  badge in it, or `:ignore`.
  """
  @spec decode(binary, integer | nil) ::
          {:joined, integer, integer, integer}
          | {:players, [{integer, integer, integer}]}
          | :ignore
  def decode(text, own_slot) do
    case json(text) do
      {:ok, [_join_ref, _ref, @topic, "phx_reply", %{"status" => "ok", "response" => response}]} ->
        joined(response)

      {:ok, [_join_ref, _ref, @topic, "snap", %{"p" => players}]}
      when is_list(players) and length(players) <= @room_max ->
        players(players, own_slot, [])

      _other ->
        :ignore
    end
  end

  defp joined(%{"room" => room, "slot" => slot, "max" => max})
       when is_integer(room) and is_integer(slot) and is_integer(max) and slot > 0 and slot <= max,
       do: {:joined, room, slot, max}

  defp joined(_response), do: :ignore

  defp players([], _own, acc), do: {:players, :lists.reverse(acc)}

  defp players([[slot, x, y] | rest], own, acc)
       when is_integer(slot) and is_integer(x) and is_integer(y) and slot > 0 and x >= 0 and
              x < @limit and y >= 0 and y < @limit do
    if slot == own, do: players(rest, own, acc), else: players(rest, own, [{slot, x, y} | acc])
  end

  defp players(_odd, _own, _acc), do: :ignore

  defp frame(join_ref, ref, topic, event, payload) do
    :erlang.iolist_to_binary(:json.encode([null(join_ref), null(ref), topic, event, payload]))
  end

  defp null(nil), do: :null
  defp null(value), do: value

  defp json(text) do
    {:ok, :json.decode(text)}
  catch
    _kind, _error -> :error
  end

  defp trim(base) do
    last = byte_size(base) - 1

    if last >= 0 and binary_part(base, last, 1) == "/",
      do: binary_part(base, 0, last),
      else: base
  end
end
