defmodule Raycaster.RelayWireTest do
  use ExUnit.Case, async: true

  alias Raycaster.RelayWire

  defp decode_json(frame), do: :json.decode(frame)

  describe "frames to the server" do
    test "join is a Phoenix frame with the ref twice" do
      assert decode_json(RelayWire.join("1")) == ["1", "1", "raycaster:lobby", "phx_join", %{}]
    end

    test "pos carries where the badge stands" do
      assert decode_json(RelayWire.pos("1", "5", 300, 400)) ==
               ["1", "5", "raycaster:lobby", "pos", %{"x" => 300, "y" => 400}]
    end

    test "the heartbeat has no join ref, and the phoenix topic" do
      assert decode_json(RelayWire.heartbeat()) == [:null, "0", "phoenix", "heartbeat", %{}]
    end
  end

  describe "url/2" do
    test "puts the path and the badge's chip on the base" do
      assert RelayWire.url("ws://192.168.1.5:4040", "A0F262EE6F6C") ==
               "ws://192.168.1.5:4040/badge/socket/websocket?vsn=2.0.0&chip=A0F262EE6F6C&name=raycaster"
    end

    test "a token, when there is one, goes on the end" do
      assert RelayWire.url("ws://h:1", "X", "s3cret-1.2_3~") ==
               RelayWire.url("ws://h:1", "X") <> "&token=s3cret-1.2_3~"
    end

    test "no token, or an empty one, adds nothing" do
      assert RelayWire.url("ws://h:1", "X", nil) == RelayWire.url("ws://h:1", "X")
      assert RelayWire.url("ws://h:1", "X", "") == RelayWire.url("ws://h:1", "X")
    end

    test "a trailing slash on the base is not doubled" do
      assert RelayWire.url("ws://h:1/", "X") == RelayWire.url("ws://h:1", "X")
    end
  end

  describe "decode/2" do
    defp reply(response),
      do: ~s(["1","1","raycaster:lobby","phx_reply",{"status":"ok","response":#{response}}])

    defp snap(players), do: ~s([null,null,"raycaster:lobby","snap",{"p":#{players}}])

    test "the answer to a join says room, slot and the most a room holds" do
      assert RelayWire.decode(reply(~s({"room":3,"slot":2,"max":8})), nil) == {:joined, 3, 2, 8}
    end

    test "a join answer that makes no sense is ignored" do
      for bad <- [
            ~s({}),
            ~s({"room":3,"slot":0,"max":8}),
            ~s({"room":3,"slot":9,"max":8}),
            ~s({"room":"x","slot":1,"max":8})
          ] do
        assert RelayWire.decode(reply(bad), nil) == :ignore
      end
    end

    test "a snapshot is everyone else in the room, by slot" do
      assert RelayWire.decode(snap("[[1,10,20],[2,30,40],[3,50,60]]"), 2) ==
               {:players, [{1, 10, 20}, {3, 50, 60}]}
    end

    test "before a badge has a slot every player is someone else" do
      assert RelayWire.decode(snap("[[1,10,20]]"), nil) == {:players, [{1, 10, 20}]}
    end

    test "an empty room is an empty list, not an error" do
      assert RelayWire.decode(snap("[]"), 1) == {:players, []}
    end

    test "a snapshot with anything odd in it is refused whole" do
      for bad <- [
            ~s([[1,10]]),
            ~s([[1,"a",2]]),
            ~s([[0,1,2]]),
            ~s([[1,-1,2]]),
            ~s([[1,4096,2]]),
            ~s([[1,1,4096]]),
            ~s([[1.5,1,2]]),
            ~s(["x"]),
            ~s([[1,1,1],[2,2]])
          ] do
        assert RelayWire.decode(snap(bad), nil) == :ignore
      end
    end

    test "more players than a room holds is not a room" do
      many = "[" <> Enum.map_join(1..17, ",", fn n -> "[#{n},1,1]" end) <> "]"

      assert RelayWire.decode(snap(many), nil) == :ignore
    end

    test "whatever else arrives is ignored" do
      for junk <- [
            "",
            "not json",
            "{}",
            "[1]",
            ~s([null,null,"chat:lobby","snap",{"p":[]}]),
            ~s([null,null,"raycaster:lobby","other",{}]),
            ~s(["1","1","raycaster:lobby","phx_reply",{"status":"error","response":{}}])
          ] do
        assert RelayWire.decode(junk, nil) == :ignore
      end
    end
  end

  describe "colour/1" do
    test "each slot of a room has its own, and they wrap after eight" do
      colours = for slot <- 1..8, do: RelayWire.colour(slot)

      assert length(Enum.uniq(colours)) == 8
      assert RelayWire.colour(9) == RelayWire.colour(1)
    end
  end
end
