defmodule Relay.Stats do
  @moduledoc """
  Counts who plays, by day, for the dashboard, and keeps the counts across restarts.

  Per day it holds two things: which badges were seen (by chip id, once each) and the
  most players there were at the same time. Nothing else about a player is kept.

  The counts live in a file, one line each time something is new:

      U 2026-10-01 A0F262EE6F6C    a badge seen for the first time that day
      P 2026-10-01 37              a new most-at-once for that day

  It is read back when the server starts, so a restart or a deploy loses nothing, as long
  as the file is on a volume (`STATS_PATH`, see the README): a Fly machine's own disk is
  wiped on every restart. A line is a few dozen bytes and there is one per badge per day,
  so the file stays small. A torn last line, or anything else that is not a line above,
  is skipped when reading. Without a place to write, the counts are kept in memory only.

  The day is the local one, `utc_offset_hours` (2, Swedish summer time) from UTC: there is
  no time zone database here.

  Only chip ids that look like a badge's, twelve hex digits, are counted. The id is what a
  client says it is, so this is a count of badges that say they are different, good enough
  for a game, and it leaves out test scripts that use other names.
  """

  use GenServer

  require Logger

  @doc """
  Options, all optional: `:path` of the file (`:stats_path` in the app config), `:name`,
  `:utc_offset_hours` (`:stats_utc_offset_hours`, 2) and `:clock`, a function giving Unix
  seconds, for tests.
  """
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "A badge with this chip id is playing. Anything but a badge's id is ignored."
  def seen(chip, server \\ __MODULE__), do: GenServer.cast(server, {:seen, chip})

  @doc "This many are playing now, all rooms together."
  def count(players, server \\ __MODULE__), do: GenServer.cast(server, {:count, players})

  @doc """
  What the dashboard shows: `%{"today" => day, "persistent" => bool, "days" => [...]}`,
  every day that has anything, oldest first, each `%{"day" =>, "unique" =>, "peak" =>}`.
  """
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, Application.get_env(:relay, :stats_path))

    offset =
      Keyword.get(
        opts,
        :utc_offset_hours,
        Application.get_env(:relay, :stats_utc_offset_hours, 2)
      )

    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)

    state = %{path: usable(path), offset: offset, clock: clock, uniques: %{}, peaks: %{}}
    {:ok, if(state.path, do: load(state), else: state)}
  end

  @impl true
  def handle_cast({:seen, chip}, state) do
    case badge_id(chip) do
      nil -> {:noreply, state}
      id -> {:noreply, see(state, today(state), id)}
    end
  end

  def handle_cast({:count, players}, state) when is_integer(players) do
    day = today(state)

    if players > Map.get(state.peaks, day, 0) do
      {:noreply,
       write(%{state | peaks: Map.put(state.peaks, day, players)}, "P #{day} #{players}")}
    else
      {:noreply, state}
    end
  end

  def handle_cast(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:snapshot, _from, state) do
    days =
      (Map.keys(state.uniques) ++ Map.keys(state.peaks))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn day ->
        %{
          "day" => day,
          "unique" => state.uniques |> Map.get(day, MapSet.new()) |> MapSet.size(),
          "peak" => Map.get(state.peaks, day, 0)
        }
      end)

    {:reply, %{"today" => today(state), "persistent" => state.path != nil, "days" => days}, state}
  end

  defp see(state, day, id) do
    ids = Map.get(state.uniques, day, MapSet.new())

    if MapSet.member?(ids, id) do
      state
    else
      write(
        %{state | uniques: Map.put(state.uniques, day, MapSet.put(ids, id))},
        "U #{day} #{id}"
      )
    end
  end

  defp today(%{clock: clock, offset: offset}) do
    (clock.() + offset * 3600) |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601()
  end

  # Twelve hex digits, in capitals, or nothing.
  defp badge_id(chip) when is_binary(chip) do
    if String.match?(chip, ~r/\A[0-9A-Fa-f]{12}\z/), do: String.upcase(chip)
  end

  defp badge_id(_other), do: nil

  # A path only when its folder is there: on Fly that is the volume being mounted.
  defp usable(nil), do: nil
  defp usable(""), do: nil

  defp usable(path) do
    if File.dir?(Path.dirname(path)) do
      path
    else
      Logger.warning("stats: #{Path.dirname(path)} is not there, counting in memory only")
      nil
    end
  end

  defp load(%{path: path} = state) do
    text =
      case File.read(path) do
        {:ok, text} -> text
        {:error, _none_yet} -> ""
      end

    # A crash in the middle of a line leaves it without its newline; the next line
    # would otherwise be glued to it.
    if text != "" and not String.ends_with?(text, "\n"), do: File.write(path, "\n", [:append])

    text |> String.split("\n", trim: true) |> Enum.reduce(state, &replay/2)
  end

  defp replay(line, state) do
    case String.split(line, " ") do
      ["U", day, chip] ->
        case {date?(day), badge_id(chip)} do
          {true, id} when is_binary(id) -> put_unique(state, day, id)
          _skip -> state
        end

      ["P", day, players] ->
        with true <- date?(day), {n, ""} when n > 0 <- Integer.parse(players) do
          %{state | peaks: Map.update(state.peaks, day, n, &max(&1, n))}
        else
          _skip -> state
        end

      _other ->
        state
    end
  end

  defp put_unique(state, day, id) do
    ids = state.uniques |> Map.get(day, MapSet.new()) |> MapSet.put(id)
    %{state | uniques: Map.put(state.uniques, day, ids)}
  end

  defp date?(text), do: match?({:ok, _date}, Date.from_iso8601(text))

  defp write(%{path: nil} = state, _line), do: state

  defp write(%{path: path} = state, line) do
    case File.write(path, line <> "\n", [:append]) do
      :ok ->
        state

      {:error, reason} ->
        Logger.warning(
          "stats: could not write #{path}: #{inspect(reason)}, counting in memory only"
        )

        %{state | path: nil}
    end
  end
end
