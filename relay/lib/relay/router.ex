defmodule Relay.Router do
  @moduledoc """
  The one path a badge connects to, the same as the chat's so a badge needs to
  know nothing new, and a page showing who is where, for a person looking.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/badge/socket/websocket" do
    conn
    |> WebSockAdapter.upgrade(Relay.Socket, [], timeout: 60_000)
    |> halt()
  end

  get "/" do
    rooms = Relay.Hub.counts()
    total = rooms |> Enum.map(fn {_room, n} -> n end) |> Enum.sum()

    lines = for {room, n} <- rooms, do: "room #{room}: #{n} playing\n"

    send_resp(
      conn,
      200,
      "raycaster relay: #{total} playing in #{length(rooms)} room(s)\n" <> Enum.join(lines)
    )
  end

  match _ do
    send_resp(conn, 404, "not found\n")
  end
end
