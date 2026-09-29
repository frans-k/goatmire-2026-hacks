defmodule Relay.Router do
  @moduledoc """
  The one path a badge connects to, the same as the chat's so a badge needs to
  know nothing new, and a page showing who is where, for a person looking.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/badge/socket/websocket" do
    conn = fetch_query_params(conn)

    cond do
      not allowed?(conn.params["token"]) ->
        send_resp(conn, 401, "unauthorized\n")

      not websocket?(conn) ->
        # Anything that is not a websocket, a browser or a scanner, gets told so
        # rather than a stack trace in the log.
        conn |> put_resp_header("upgrade", "websocket") |> send_resp(426, "upgrade required\n")

      true ->
        conn
        |> WebSockAdapter.upgrade(Relay.Socket, [], timeout: 60_000)
        |> halt()
    end
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

  defp websocket?(conn) do
    conn |> get_req_header("upgrade") |> Enum.any?(&(String.downcase(&1) == "websocket"))
  end

  # No token set means anyone may join. Compared in constant time.
  defp allowed?(sent) do
    case Application.get_env(:relay, :token) do
      nil -> true
      "" -> true
      token -> is_binary(sent) and Plug.Crypto.secure_compare(sent, token)
    end
  end
end
