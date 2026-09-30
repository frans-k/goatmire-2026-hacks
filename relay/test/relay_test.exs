defmodule Relay.Client do
  @moduledoc false
  use WebSockex

  @url "ws://127.0.0.1:4041/badge/socket/websocket?vsn=2.0.0&chip=TEST&name=test"

  def start(extra \\ ""), do: WebSockex.start_link(@url <> extra, __MODULE__, self())

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

  test "the snapshot says where the goat is" do
    a = connect()
    join(a)

    assert_receive {:frame, ^a, [nil, nil, @topic, "snap", %{"g" => [x, y, hunting]}]}, 1_000
    assert x in 0..4_095 and y in 0..4_095 and hunting in [0, 1]
  end

  test "a badge the goat reaches is told so, is out, and can come back" do
    a = connect()
    %{"slot" => slot} = join(a)
    assert_receive {:frame, ^a, [nil, nil, @topic, "snap", %{"g" => [x, y, _hunting]}]}, 1_000

    Client.push(a, [nil, nil, @topic, "pos", %{"x" => x, "y" => y}])
    assert_receive {:frame, ^a, [nil, nil, @topic, "caught", %{}]}, 1_000
    assert snapshot_where(a, &(&1 == [])) == []

    Client.push(a, [nil, nil, @topic, "respawn", %{}])
    Process.sleep(100)
    Client.push(a, [nil, nil, @topic, "pos", %{"x" => 384, "y" => 384}])

    assert snapshot_where(a, &(&1 == [[slot, 384, 384]])) == [[slot, 384, 384]]
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

  describe "what is not a websocket" do
    defp http_get(path) do
      {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", 4041, [:binary, active: false])
      :ok = :gen_tcp.send(socket, "GET #{path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
      {:ok, reply} = :gen_tcp.recv(socket, 0, 2_000)
      :gen_tcp.close(socket)
      reply
    end

    test "a plain request to the badge path is told to upgrade, not given an error" do
      assert "HTTP/1.1 426" <> _ = http_get("/badge/socket/websocket")
    end

    test "the status page answers, and anything else is not found" do
      assert "HTTP/1.1 200" <> _ = http_get("/")
      assert "HTTP/1.1 404" <> _ = http_get("/nothing/here")
    end
  end

  describe "a token, when the server has one" do
    setup do
      Application.put_env(:relay, :token, "s3cret")
      on_exit(fn -> Application.delete_env(:relay, :token) end)
    end

    test "a badge without it is refused" do
      Process.flag(:trap_exit, true)

      assert {:error, %WebSockex.RequestError{code: 401}} = Client.start()
    end

    test "so is one with the wrong token, and one with a token of another length" do
      Process.flag(:trap_exit, true)

      assert {:error, %WebSockex.RequestError{code: 401}} = Client.start("&token=wrong!")
      assert {:error, %WebSockex.RequestError{code: 401}} = Client.start("&token=s3cre")
      assert {:error, %WebSockex.RequestError{code: 401}} = Client.start("&token=")
    end

    test "one with the token joins as usual" do
      {:ok, client} = Client.start("&token=s3cret")

      assert %{"room" => 1, "slot" => 1} = join(client)
    end

    test "and refusing one leaves nobody in a room" do
      Process.flag(:trap_exit, true)
      Client.start("&token=nope")
      Process.sleep(100)

      assert Relay.Hub.counts() == []
    end
  end

  describe "the most players the server holds" do
    setup do
      Application.put_env(:relay, :max_players, 2)
      on_exit(fn -> Application.delete_env(:relay, :max_players) end)
    end

    test "the one past it is told the server is full, and the others are not disturbed" do
      a = connect()
      %{"slot" => 1} = join(a)
      b = connect()
      %{"slot" => 2} = join(b)
      c = connect()

      Client.push(c, ["9", "9", @topic, "phx_join", %{}])

      assert_receive {:frame, ^c,
                      [
                        "9",
                        "9",
                        @topic,
                        "phx_reply",
                        %{"status" => "error", "response" => %{"reason" => "full"}}
                      ]},
                     1_000

      assert Relay.Hub.counts() == [{1, 2}]

      Client.push(a, [nil, nil, @topic, "pos", %{"x" => 7, "y" => 8}])
      assert snapshot_where(b, &(&1 == [[1, 7, 8]])) == [[1, 7, 8]]
    end

    test "a place opens up again when someone leaves" do
      a = connect()
      join(a)
      b = connect()
      join(b)
      c = connect()

      Client.push(a, ["1", "2", @topic, "phx_leave", %{}])
      assert_receive {:frame, ^a, ["1", "2", @topic, "phx_reply", _]}, 1_000
      Process.sleep(100)

      assert %{"slot" => 1} = join(c)
    end
  end
end
