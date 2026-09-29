defmodule Raycaster.WireTest do
  use ExUnit.Case, async: true

  alias Raycaster.Wire

  @pose %{x: 1_000, y: 2_345, a: 40_000}

  describe "encode/2 and decode/1" do
    test "a position and colour survive the round trip" do
      assert {:ok, %{x: 1_000, y: 2_345, a: 40_000, colour: 0xE0433A}} =
               Wire.decode(Wire.encode(@pose, 0xE0433A))
    end

    test "is 9 bytes" do
      assert byte_size(Wire.encode(@pose, 0x102030)) == 9
    end

    test "an angle that has wrapped past a turn, or gone negative, still fits" do
      assert {:ok, %{a: a}} = Wire.decode(Wire.encode(%{@pose | a: 70_000}, 0))
      assert a == 70_000 - 65_536

      assert {:ok, %{a: 65_535}} = Wire.decode(Wire.encode(%{@pose | a: -1}, 0))
    end
  end

  describe "decode/1 of what anyone can publish" do
    test "empty means the badge has left" do
      assert Wire.decode(<<>>) == :gone
    end

    test "the wrong length is refused" do
      assert Wire.decode(<<1, 2, 3>>) == :error
      assert Wire.decode(:binary.copy(<<0>>, 10)) == :error
    end

    test "a position outside the 16 by 16 map is refused, not clamped" do
      assert Wire.decode(<<4_096::16, 0::16, 0::16, 0, 0, 0>>) == :error
      assert Wire.decode(<<0::16, 65_535::16, 0::16, 0, 0, 0>>) == :error
      assert {:ok, _pose} = Wire.decode(<<4_095::16, 4_095::16, 0::16, 0, 0, 0>>)
    end
  end

  describe "topics" do
    test "a badge's topic is under the prefix, and its id comes back out" do
      assert Wire.topic("A0F262EE6F6C") == "goatmire/raycaster/v1/A0F262EE6F6C"
      assert Wire.id(Wire.topic("A0F262EE6F6C")) == {:ok, "A0F262EE6F6C"}
    end

    test "the filter hears every badge" do
      assert Wire.filter() == "goatmire/raycaster/v1/+"
    end

    test "a topic that is not one of ours has no id" do
      assert Wire.id("goatmire/chat/v1/X") == :error
      assert Wire.id("goatmire/raycaster/v1/") == :error
      assert Wire.id("goatmire/raycaster/v1/A/B") == :error
      assert Wire.id("") == :error
    end
  end

  describe "colour/1" do
    test "is the same for the same chip, and from the palette" do
      chip = <<0xA0, 0xF2, 0x62, 0xEE, 0x6F, 0x6C>>

      assert Wire.colour(chip) == Wire.colour(chip)

      assert Wire.colour(chip) in [
               0xE0433A,
               0x3AA0E0,
               0x3AE07A,
               0xE0C93A,
               0xB03AE0,
               0xE07A3A,
               0x3AE0D4,
               0xE03A9A
             ]
    end

    test "different chips do not all get one colour" do
      colours = for n <- 0..15, do: Wire.colour(<<0, 0, 0, 0, 0, n>>)

      assert length(Enum.uniq(colours)) > 4
    end
  end

  describe "broker/1" do
    test "defaults to a public broker when nothing is set" do
      assert Wire.broker(nil) == {~c"test.mosquitto.org", 1883}
      assert Wire.broker("") == {~c"test.mosquitto.org", 1883}
    end

    test "takes a host, with or without a port" do
      assert Wire.broker("10.0.0.5") == {~c"10.0.0.5", 1883}
      assert Wire.broker("10.0.0.5:8883") == {~c"10.0.0.5", 8883}
      assert Wire.broker("broker.local:65535") == {~c"broker.local", 65_535}
    end

    test "a port that is not one falls back to the default" do
      for bad <- ["x", "", "0", "65536", "99999999999", "12ab"] do
        assert Wire.broker("host:" <> bad) == {~c"host", 1883}
      end
    end
  end
end
