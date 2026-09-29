defmodule Relay.Client do
  @moduledoc false
  use WebSockex

  @url "ws://127.0.0.1:4041/badge/socket/websocket?vsn=2.0.0&chip=TEST&name=test"

  def start, do: WebSockex.start_link(@url, __MODULE__, self())

  def push(client, frame), do: WebSockex.send_frame(client, {:text, JSON.encode!(frame)})
  def push_raw(client, text), do: WebSockex.send_frame(client, {:text, text})

  @impl true
  def handle_frame({:text, text}, owner) do
    send(owner, {:frame, self(), JSON.decode!(text)})
    {:ok, owner}
  end
end

defmodule Relay.RelayTest do
  # One hub for the whole app, so these cannot run side by side.
  use ExUnit.Case, async: false

  alias Relay.Client

  @topic "raycaster:lobby"

  defp connect do
    {:ok, client} = Client.start()
    client
  end

  defp join(client, ref \\ "1") do
    Client.push(client, [ref, ref, @topic, "phx_join", %{}])

    assert_receive {:frame, ^client,
                    [^ref, ^ref, @topic, "phx_reply", %{"status" => "ok", "response" => response}]},
                   1_000

    response
  end

  defp snapshot(client) do
    assert_receive {:frame, ^client, [nil, nil, @topic, "snap", %{"p" => players}]}, 1_000
    players
  end

  # The hub ticks every 50 ms here, so wait for one that has what is wanted.
  defp snapshot_where(client, fun, tries \\ 40) do
    players = snapshot(client)

    cond do
      fun.(players) -> players
      tries == 0 -> flunk("never saw the snapshot wanted, last was #{inspect(players)}")
      true -> snapshot_where(client, fun, tries - 1)
    end
  end

  setup do
    # Whoever the last test left behind has gone by now, but the hub hears of it
    # a moment after the socket closes.
    Process.sleep(100)
    :ok
  end

  test "a badge that joins is told its room and slot" do
    client = connect()

    assert %{"room" => 1, "slot" => 1, "max" => 8} = join(client)
  end

  test "the next badge is in the same room, in the next slot" do
    first = connect()
    join(first)
    second = connect()

    assert %{"room" => 1, "slot" => 2} = join(second)
  end

  test "each badge is told where the others are, once a tick, and itself among them" do
    a = connect()
    %{"slot" => slot_a} = join(a)
    b = connect()
    %{"slot" => slot_b} = join(b)

    Client.push(a, [nil, nil, @topic, "pos", %{"x" => 300, "y" => 400}])
    Client.push(b, [nil, nil, @topic, "pos", %{"x" => 900, "y" => 1000}])

    want = [[slot_a, 300, 400], [slot_b, 900, 1000]]

    assert snapshot_where(a, &(&1 == want)) == want
    assert snapshot_where(b, &(&1 == want)) == want
  end

  test "the ninth badge is put in a second room by itself" do
    clients = for _ <- 1..9, do: connect()
    places = for {client, n} <- Enum.with_index(clients, 1), do: join(client, "#{n}")

    assert Enum.count(places, &(&1["room"] == 1)) == 8
    assert %{"room" => 2, "slot" => 1} = List.last(places)
  end

  test "a badge that goes away is out of the snapshot at once" do
    a = connect()
    join(a)
    b = connect()
    %{"slot" => slot_b} = join(b)
    Client.push(b, [nil, nil, @topic, "pos", %{"x" => 5, "y" => 6}])
    snapshot_where(a, &(&1 == [[slot_b, 5, 6]]))

    # Linked to this test, so let go before it goes: it dies without saying goodbye,
    # as a badge that loses power does.
    Process.unlink(b)
    Process.exit(b, :kill)

    assert snapshot_where(a, &(&1 == [])) == []
  end

  test "a position outside the map is not passed on" do
    a = connect()
    %{"slot" => slot} = join(a)
    Client.push(a, [nil, nil, @topic, "pos", %{"x" => 99_999, "y" => 5}])
    Process.sleep(150)

    assert snapshot(a) == []

    Process.sleep(250)
    Client.push(a, [nil, nil, @topic, "pos", %{"x" => 10, "y" => 20}])
    assert snapshot_where(a, &(&1 == [[slot, 10, 20]])) == [[slot, 10, 20]]
  end

  test "a position sent before joining is ignored" do
    a = connect()
    Client.push(a, [nil, nil, @topic, "pos", %{"x" => 1, "y" => 2}])
    Process.sleep(100)
    %{"slot" => slot} = join(a)

    assert snapshot(a) == []
    assert slot == 1
  end

  test "the heartbeat is answered as Phoenix answers it" do
    a = connect()
    Client.push(a, [nil, "7", "phoenix", "heartbeat", %{}])

    assert_receive {:frame, ^a, [nil, "7", "phoenix", "phx_reply", %{"status" => "ok"}]}, 1_000
  end

  test "another topic is refused, not ignored" do
    a = connect()
    Client.push(a, ["1", "1", "chat:lobby", "phx_join", %{}])

    assert_receive {:frame, ^a, ["1", "1", "chat:lobby", "phx_reply", %{"status" => "error"}]},
                   1_000
  end

  test "nonsense does not hurt it, and the badge can carry on" do
    a = connect()

    for junk <- ["", "not json", "{}", "[1,2]", "[null,null,1,2,3]", ~s([null,null,"x","y","z"])] do
      Client.push_raw(a, junk)
    end

    assert %{"slot" => 1} = join(a)
  end

  test "leaving takes the badge out of its room" do
    a = connect()
    join(a)
    Client.push(a, ["1", "2", @topic, "phx_leave", %{}])

    assert_receive {:frame, ^a, ["1", "2", @topic, "phx_reply", %{"status" => "ok"}]}, 1_000
    Process.sleep(100)
    assert Relay.Hub.counts() == []
  end
end
