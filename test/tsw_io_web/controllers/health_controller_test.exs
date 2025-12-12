defmodule TswIoWeb.HealthControllerTest do
  use TswIoWeb.ConnCase, async: true

  describe "GET /api/health" do
    test "returns 200 with ok status when database is ready", %{conn: conn} do
      conn = get(conn, ~p"/api/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "response includes proper content type", %{conn: conn} do
      conn = get(conn, ~p"/api/health")

      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end
  end
end
