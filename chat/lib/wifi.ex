defmodule MyHack.Wifi do
  @moduledoc """
  Association and DHCP around the AtomVM network API.
  """

  @retry_delay_ms 2_000

  # wait_for_sta/2 returns once the badge has associated and DHCP has given it
  # an address, or with an error when neither happens in time. A single scan
  # can miss the access point, so a failed attempt is retried a few times.
  def connect(ssid, psk, attempts \\ 5) do
    # The network driver wants charlists; binaries are not reliably accepted.
    config = [
      ssid: :erlang.binary_to_list(ssid),
      psk: :erlang.binary_to_list(psk),
      dhcp_hostname: ~c"avm-badge"
    ]

    case :network.wait_for_sta(config, 30_000) do
      {:ok, {address, _netmask, _gateway}} ->
        {:ok, format(address)}

      {:error, reason} when attempts > 1 ->
        IO.puts("WiFi failed (#{inspect(reason)}), retrying, #{attempts - 1} left")
        reset()
        connect(ssid, psk, attempts - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A failed wait_for_sta leaves the network server running, and starting it a
  # second time would return already_started, so stop it and drop stale events.
  defp reset do
    :network.stop()
    flush()
    :timer.sleep(@retry_delay_ms)
  end

  defp flush do
    receive do
      :connected -> flush()
      :disconnected -> flush()
      {:ok, _ip_info} -> flush()
    after
      0 -> :ok
    end
  end

  defp format({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
end
