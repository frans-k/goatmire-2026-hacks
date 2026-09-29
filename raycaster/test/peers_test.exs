defmodule Raycaster.PeersTest do
  use ExUnit.Case, async: true

  alias Raycaster.Peers

  defp pose(x), do: %{x: x, y: 500, a: 0, colour: 0xE0433A}

  test "starts empty" do
    assert Peers.new() == []
    assert Peers.count(Peers.new()) == 0
  end

  test "hearing from someone twice keeps one entry, at the new place" do
    peers = Peers.new() |> Peers.put("A", pose(100), 0) |> Peers.put("A", pose(200), 50)

    assert Peers.count(peers) == 1
    assert Peers.others(peers, 50) == [{200, 500, 0xE0433A}]
  end

  test "others/1 is what the engine takes" do
    peers = Peers.new() |> Peers.put("A", pose(100), 0) |> Peers.put("B", pose(300), 0)

    assert Enum.sort(Peers.others(peers, 0)) == [{100, 500, 0xE0433A}, {300, 500, 0xE0433A}]
  end

  test "drop/2 removes one" do
    peers = Peers.new() |> Peers.put("A", pose(100), 0) |> Peers.put("B", pose(300), 0)

    assert Peers.count(Peers.drop(peers, "A")) == 1
    assert Peers.drop(peers, "nobody") == peers
  end

  describe "expire/2" do
    test "forgets who has not been heard from for four seconds" do
      peers = Peers.new() |> Peers.put("old", pose(1), 0) |> Peers.put("new", pose(2), 3_500)

      assert [{"new", _pose, 3_500, nil, nil}] = Peers.expire(peers, 4_000)
    end

    test "keeps everyone heard from just inside the limit" do
      peers = Peers.new() |> Peers.put("A", pose(1), 1_000)

      assert Peers.expire(peers, 4_999) == peers
      assert Peers.expire(peers, 5_000) == []
    end

    test "returns the very same list when nobody has expired, so a page is not redrawn for it" do
      peers = Peers.new() |> Peers.put("A", pose(1), 0) |> Peers.put("B", pose(2), 10)

      assert Peers.expire(peers, 100) === peers
    end
  end

  test "the table is capped, keeping the most recently heard from" do
    peers = Enum.reduce(1..30, Peers.new(), fn n, acc -> Peers.put(acc, "id#{n}", pose(n), n) end)

    assert Peers.count(peers) == 12
    assert Enum.any?(peers, fn {id, _pose, _seen, _before, _before_seen} -> id == "id30" end)
    refute Enum.any?(peers, fn {id, _pose, _seen, _before, _before_seen} -> id == "id1" end)
  end

  describe "extrapolation" do
    # Walking east at 100 units every 500 ms.
    defp walking do
      Peers.new() |> Peers.put("A", pose(1_000), 0) |> Peers.put("A", pose(1_100), 500)
    end

    test "a player heard once is where it said, however long ago" do
      peers = Peers.put(Peers.new(), "A", pose(1_000), 0)

      assert Peers.others(peers, 0) == [{1_000, 500, 0xE0433A}]
      assert Peers.others(peers, 500) == [{1_000, 500, 0xE0433A}]
    end

    test "a player on the move is drawn where it would be by now" do
      assert Peers.others(walking(), 500) == [{1_100, 500, 0xE0433A}]
      assert Peers.others(walking(), 750) == [{1_150, 500, 0xE0433A}]
      assert Peers.others(walking(), 1_000) == [{1_200, 500, 0xE0433A}]
    end

    test "but not for long: it stops going on after 600 ms" do
      assert Peers.others(walking(), 1_100) == [{1_220, 500, 0xE0433A}]
      assert Peers.others(walking(), 5_000) == [{1_220, 500, 0xE0433A}]
    end

    test "a player that stood still and then moved says nothing about speed" do
      peers = Peers.new() |> Peers.put("A", pose(1_000), 0) |> Peers.put("A", pose(2_000), 1_500)

      assert Peers.others(peers, 1_800) == [{2_000, 500, 0xE0433A}]
    end

    test "updates too close together say nothing about speed either" do
      peers = Peers.new() |> Peers.put("A", pose(1_000), 0) |> Peers.put("A", pose(1_100), 10)

      assert Peers.others(peers, 200) == [{1_100, 500, 0xE0433A}]
    end

    test "never runs off the map" do
      peers = Peers.new() |> Peers.put("A", pose(4_000), 0) |> Peers.put("A", pose(4_090), 500)

      assert [{x, _y, _c}] = Peers.others(peers, 1_100)
      assert x == 4_095

      back = Peers.new() |> Peers.put("A", pose(90), 0) |> Peers.put("A", pose(0), 500)
      assert [{0, _y, _c}] = Peers.others(back, 1_100)
    end

    test "moving?/2 is true while someone is being carried along, and only then" do
      assert Peers.moving?(walking(), 700)
      refute Peers.moving?(walking(), 1_200)
      refute Peers.moving?(Peers.new(), 0)
      refute Peers.moving?(Peers.put(Peers.new(), "A", pose(1_000), 0), 100)

      standing = Peers.new() |> Peers.put("A", pose(1_000), 0) |> Peers.put("A", pose(1_000), 500)
      refute Peers.moving?(standing, 600)
    end
  end
end
