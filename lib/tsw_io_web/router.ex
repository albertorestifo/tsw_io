defmodule TswIoWeb.Router do
  use TswIoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TswIoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TswIoWeb do
    pipe_through :browser

    live_session :default, on_mount: TswIoWeb.NavHook do
      live "/", ConfigurationListLive
      live "/configurations/:config_id", ConfigurationEditLive
      live "/simulator/config", SimulatorConfigLive
      live "/trains", TrainListLive
      live "/trains/:train_id", TrainEditLive
      live "/firmware", FirmwareLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TswIoWeb do
  #   pipe_through :api
  # end

end
