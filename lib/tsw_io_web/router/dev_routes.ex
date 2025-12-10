if Code.ensure_loaded?(Phoenix.LiveDashboard.Router) do
  defmodule TswIoWeb.Router.DevRoutes do
    @moduledoc """
    Development-only routes for debugging tools.
    This module is only compiled when phoenix_live_dashboard is available.
    """
    use TswIoWeb, :router

    import Phoenix.LiveDashboard.Router

    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :put_root_layout, html: {TswIoWeb.Layouts, :root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TswIoWeb.Telemetry
    end
  end
end
