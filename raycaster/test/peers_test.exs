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
    assert Peers.others(peers) == [{200, 500, 0xE0433A}]
  end

  test "others/1 is what the engine takes" do
    peers = Peers.new() |> Peers.put("A", pose(100), 0) |> Peers.put("B", pose(300), 0)

    assert Enum.sort(Peers.others(peers)) == [{100, 500, 0xE0433A}, {300, 500, 0xE0433A}]
  end

  test "drop/2 removes one" do
    peers = Peers.new() |> Peers.put("A", pose(100), 0) |> Peers.put("B", pose(300), 0)

    assert Peers.count(Peers.drop(peers, "A")) == 1
    assert Peers.drop(peers, "nobody") == peers
  end

  describe "expire/2" do
    test "forgets who has not been heard from for four seconds" do
      peers = Peers.new() |> Peers.put("old", pose(1), 0) |> Peers.put("new", pose(2), 3_500)

      assert [{"new", _pose, 3_500}] = Peers.expire(peers, 4_000)
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
    assert Enum.any?(peers, fn {id, _pose, _seen} -> id == "id30" end)
    refute Enum.any?(peers, fn {id, _pose, _seen} -> id == "id1" end)
  end
end
