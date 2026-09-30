defmodule Raycaster.Wifi do
  @moduledoc """
  Association and DHCP around the AtomVM network API.
  """

  @retry_delay_ms 2_000

  @doc """
  The network to join, as `{ssid, psk}`, or nil for none. Credentials compiled in win.
  Without them, and when `from_nvs` is set, it is the network the badge already knows:
  the badge's own firmware keeps what is typed under Settings, Wifi in the `badge` NVS
  namespace as `wifi_ssid` and `wifi_psk`, and flashing over it leaves NVS alone. A
  build made this way carries no password.
  """
  def credentials(ssid, psk, _from_nvs) when is_binary(ssid), do: {ssid, psk || ""}

  def credentials(_no_ssid, _psk, true) do
    case nvs(:wifi_ssid) do
      ssid when is_binary(ssid) and ssid != "" ->
        case nvs(:wifi_psk) do
          psk when is_binary(psk) -> {ssid, psk}
          _open -> {ssid, ""}
        end

      _none ->
        nil
    end
  end

  def credentials(_no_ssid, _psk, _from_nvs), do: nil

  # AtomVM answers :undefined for a key that is not there. On the laptop there is no NVS at
  # all, which is the same as nothing stored.
  defp nvs(key) do
    case :esp.nvs_get_binary(:badge, key) do
      :undefined -> nil
      value -> value
    end
  catch
    _kind, _reason -> nil
  end

  # wait_for_sta/2 returns once the badge has associated and DHCP has given it
  # an address, or with an error when neither happens in time. A single scan
  # can miss the access point, so a failed attempt is retried a few times.
  def connect(ssid, psk, attempts \\ 5) do
    # The network driver wants charlists; binaries are not reliably accepted.
    # The clock is set over SNTP, and the caller is sent `{:synchronized, time}`:
    # a certificate is not yet valid at the epoch, so a `wss://` connection has to
    # wait for it.
    caller = self()

    # An open network has no psk at all, which is not the same as an empty one.
    psk_option = if psk == "", do: [], else: [psk: :erlang.binary_to_list(psk)]

    config =
      [ssid: :erlang.binary_to_list(ssid)] ++
        psk_option ++
        [
          dhcp_hostname: ~c"avm-raycaster",
          sntp: [
            host: "pool.ntp.org",
            synchronized: fn time -> send(caller, {:synchronized, time}) end
          ]
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
