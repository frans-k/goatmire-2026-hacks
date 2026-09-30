defmodule Raycaster.WifiTest do
  use ExUnit.Case, async: true

  alias Raycaster.Wifi

  # The badge's NVS holds nothing on the laptop, which is what these rely on for the
  # "from NVS" cases: there is no :esp here, and that reads as nothing stored.
  describe "credentials/3" do
    test "a compiled-in network is used as given" do
      assert Wifi.credentials("cafe", "secret", false) == {"cafe", "secret"}
      assert Wifi.credentials("cafe", "secret", true) == {"cafe", "secret"}
    end

    test "a compiled-in open network has an empty passphrase" do
      assert Wifi.credentials("cafe", nil, false) == {"cafe", ""}
      assert Wifi.credentials("cafe", "", true) == {"cafe", ""}
    end

    test "no network compiled in and NVS not asked for means none" do
      assert Wifi.credentials(nil, nil, false) == nil
    end

    test "reading the badge's own network finds nothing where there is no NVS" do
      assert Wifi.credentials(nil, nil, true) == nil
    end
  end
end
