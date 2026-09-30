defmodule Relay.StatsTest do
  use ExUnit.Case, async: true

  alias Relay.Stats

  # 10:00 UTC on 1 October 2026, which is 12:00 in Sweden.
  @noon DateTime.to_unix(DateTime.new!(~D[2026-10-01], ~T[10:00:00], "Etc/UTC"))
  @day 86_400

  @a "A0F262EE6F6C"
  @b "A0F262EE6F6D"

  @moduletag :tmp_dir

  # A clock the test moves, and a name of its own so tests can run side by side.
  defp start(tmp_dir, opts \\ []) do
    name = :"stats_#{System.unique_integer([:positive])}"
    {:ok, clock} = Agent.start_link(fn -> Keyword.get(opts, :at, @noon) end)
    path = Keyword.get(opts, :path, Path.join(tmp_dir, "players.log"))

    start_opts = [name: name, path: path, clock: fn -> Agent.get(clock, & &1) end]
    {:ok, pid} = Stats.start_link(start_opts)
    %{name: name, pid: pid, clock: clock, path: path, opts: start_opts}
  end

  defp at(%{clock: clock}, seconds), do: Agent.update(clock, fn _ -> seconds end)

  # A call after the casts, which are handled in order, so their effect is there. The
  # clock is read when a message is handled, so this is also how a test lets what it sent
  # count on the day it was sent before it moves the clock.
  defp days(%{name: name}), do: Stats.snapshot(name)["days"]

  test "a badge is counted once a day, however often it joins", %{tmp_dir: dir} do
    s = start(dir)
    for _ <- 1..3, do: Stats.seen(@a, s.name)
    Stats.seen(@b, s.name)

    assert [%{"day" => "2026-10-01", "unique" => 2}] = days(s)
  end

  test "the same badge counts again the next day, and days come oldest first", %{tmp_dir: dir} do
    s = start(dir)
    Stats.seen(@a, s.name)
    days(s)
    at(s, @noon + @day)
    Stats.seen(@a, s.name)

    assert [%{"day" => "2026-10-01", "unique" => 1}, %{"day" => "2026-10-02", "unique" => 1}] =
             days(s)

    assert Stats.snapshot(s.name)["today"] == "2026-10-02"
  end

  test "only twelve hex digits are a badge, in either case", %{tmp_dir: dir} do
    s = start(dir)

    for junk <- ["TEST", "STRESS001", "GHOST01", "", "A0F262EE6F6C1", "A0F262EE6F6G", nil, 42] do
      Stats.seen(junk, s.name)
    end

    assert days(s) == []

    Stats.seen(String.downcase(@a), s.name)
    Stats.seen(@a, s.name)
    assert [%{"unique" => 1}] = days(s)
  end

  test "the most at once only goes up, within a day", %{tmp_dir: dir} do
    s = start(dir)
    for n <- [3, 7, 5, 7, 2], do: Stats.count(n, s.name)
    assert [%{"peak" => 7}] = days(s)

    at(s, @noon + @day)
    Stats.count(4, s.name)
    assert [%{"peak" => 7}, %{"peak" => 4}] = days(s)
  end

  test "the day turns over at midnight in Sweden, not in UTC", %{tmp_dir: dir} do
    # 21:59:59 UTC is 23:59:59 in Sweden, and one second later it is the next day.
    before_midnight = DateTime.to_unix(DateTime.new!(~D[2026-10-01], ~T[21:59:59], "Etc/UTC"))
    s = start(dir, at: before_midnight)

    Stats.seen(@a, s.name)
    days(s)
    at(s, before_midnight + 1)
    Stats.seen(@b, s.name)

    assert [%{"day" => "2026-10-01", "unique" => 1}, %{"day" => "2026-10-02", "unique" => 1}] =
             days(s)
  end

  describe "the file" do
    test "has one line for each new badge and each new peak", %{tmp_dir: dir} do
      s = start(dir)
      Stats.seen(@a, s.name)
      Stats.seen(@a, s.name)
      Stats.count(3, s.name)
      Stats.count(2, s.name)
      Stats.count(5, s.name)
      days(s)

      assert File.read!(s.path) == "U 2026-10-01 #{@a}\nP 2026-10-01 3\nP 2026-10-01 5\n"
    end

    test "gives the same counts after a restart", %{tmp_dir: dir} do
      first = start(dir)
      Stats.seen(@a, first.name)
      Stats.seen(@b, first.name)
      Stats.count(6, first.name)
      before = days(first)
      GenServer.stop(first.pid)

      again = start(dir)
      assert days(again) == before
      assert [%{"unique" => 2, "peak" => 6}] = before

      # And a badge seen before the restart is not counted twice.
      Stats.seen(@a, again.name)
      assert [%{"unique" => 2}] = days(again)
    end

    test "skips lines that are not its own, and a torn last line, and goes on writing", %{
      tmp_dir: dir
    } do
      path = Path.join(dir, "players.log")

      File.write!(
        path,
        "U 2026-10-01 #{@a}\nnonsense\nU 2026-13-45 #{@b}\nU 2026-10-01 STRESS001\nP 2026-10-01 x\nP 2026-10-01 4\nU 2026-10-01 A0F2"
      )

      s = start(dir, path: path)
      assert [%{"day" => "2026-10-01", "unique" => 1, "peak" => 4}] = days(s)

      # A new line must not be glued to the torn one.
      Stats.seen(@b, s.name)
      days(s)
      GenServer.stop(s.pid)

      again = start(dir, path: path)
      assert [%{"unique" => 2, "peak" => 4}] = days(again)
    end

    test "counts in memory only when its folder is not there", %{tmp_dir: dir} do
      s = start(dir, path: Path.join([dir, "no", "such", "players.log"]))
      Stats.seen(@a, s.name)

      assert %{"persistent" => false, "days" => [%{"unique" => 1}]} = Stats.snapshot(s.name)
      refute File.exists?(Path.join(dir, "no"))
    end

    test "says it is persistent when it has a file", %{tmp_dir: dir} do
      assert %{"persistent" => true} = Stats.snapshot(start(dir).name)
    end
  end
end
