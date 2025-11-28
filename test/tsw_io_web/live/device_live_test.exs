defmodule TswIoWeb.DeviceLiveTest do
  use TswIoWeb.ConnCase

  test "GET / renders device live", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    # Always present regardless of device state
    assert html =~ "TWS IO"

    # Either shows "No Devices Connected" or shows device count
    # (depends on whether physical devices are connected during test)
    assert html =~ "No Devices Connected" or html =~ "Device"
  end
end
