defmodule Raycaster.Wire do
  @moduledoc """
  What badges tell each other while they play, and where.

  A badge publishes its position, 9 bytes, to `goatmire/raycaster/v1/<its chip id>`
  and listens on `goatmire/raycaster/v1/+`. An empty payload on a badge's own topic
  means it has left, which is also what the broker sends on its behalf when the
  link dies.

      <<x::16, y::16, a::16, red, green, blue>>

  `x` and `y` are in the engine's fixed point, 256 to a map cell, and `a` is its
  angle, 65536 to a turn. The broker is open to anyone, so `decode/1` treats every
  payload as untrusted: a position outside the map is refused, not clamped.
  """

  import Bitwise

  @prefix "goatmire/raycaster/v1/"

  # The map is 16 cells across.
  @limit 16 * 256

  @default_host ~c"test.mosquitto.org"
  @default_port 1883

  # Bright enough to read against the walls, one to a badge by its chip id.
  @colours {0xE0433A, 0x3AA0E0, 0x3AE07A, 0xE0C93A, 0xB03AE0, 0xE07A3A, 0x3AE0D4, 0xE03A9A}

  @doc "The topic a badge publishes to, from its chip id written out as hex."
  @spec topic(binary) :: binary
  def topic(id), do: @prefix <> id

  @doc "The subscription that hears every badge."
  @spec filter() :: binary
  def filter, do: @prefix <> "+"

  @doc "The chip id in a topic, or `:error` if it is not one of ours."
  @spec id(binary) :: {:ok, binary} | :error
  def id(topic) do
    case topic do
      <<@prefix::binary, rest::binary>> when byte_size(rest) > 0 ->
        if :binary.match(rest, "/") == :nomatch, do: {:ok, rest}, else: :error

      _other ->
        :error
    end
  end

  @doc "A badge's colour, always the same one, from its six-byte chip id."
  @spec colour(binary) :: non_neg_integer
  def colour(chip_id) do
    # lists:sum/1 is not in AtomVM's lists.
    sum = :lists.foldl(fn byte, total -> total + byte end, 0, :erlang.binary_to_list(chip_id))

    elem(@colours, rem(sum, tuple_size(@colours)))
  end

  @doc "A position and a colour as a payload."
  @spec encode(map, non_neg_integer) :: binary
  def encode(%{x: x, y: y, a: a}, colour) do
    <<x &&& 0xFFFF::16, y &&& 0xFFFF::16, a &&& 0xFFFF::16, colour >>> 16 &&& 255::8,
      colour >>> 8 &&& 255::8, colour &&& 255::8>>
  end

  @doc "A payload as a position and colour, `:gone` for an empty one, or `:error`."
  @spec decode(binary) :: {:ok, map} | :gone | :error
  def decode(<<>>), do: :gone

  def decode(<<x::16, y::16, a::16, red, green, blue>>) when x < @limit and y < @limit do
    {:ok, %{x: x, y: y, a: a, colour: red <<< 16 ||| green <<< 8 ||| blue}}
  end

  def decode(_other), do: :error

  @doc """
  The broker to use, as `{host, port}`: a setting, `host` or
  `host:port`, or a public one when there is none. The host is a charlist,
  because that is what AtomVM's sockets resolve.
  """
  @spec broker(binary | nil) :: {charlist, non_neg_integer}
  def broker(nil), do: {@default_host, @default_port}
  def broker(""), do: {@default_host, @default_port}

  def broker(setting) do
    case :binary.split(setting, ":") do
      [host, port] -> {:erlang.binary_to_list(host), port(port)}
      [host] -> {:erlang.binary_to_list(host), @default_port}
    end
  end

  # Digits only, and 1 to 65535: anything else falls back to the default.
  defp port(text), do: digits(text, 0)

  defp digits(<<>>, port) when port > 0 and port < 65_536, do: port
  defp digits(<<>>, _port), do: @default_port

  defp digits(<<digit, rest::binary>>, port) when digit >= ?0 and digit <= ?9 and port <= 6_553 do
    digits(rest, port * 10 + digit - ?0)
  end

  defp digits(_other, _port), do: @default_port
end
