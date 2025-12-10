defmodule TswIo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        TswIoWeb.Telemetry,
        TswIo.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:tsw_io, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:tsw_io, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: TswIo.PubSub},
        {Registry, keys: :unique, name: TswIo.Registry},
        TswIo.Serial.Connection,
        TswIo.Hardware.ConfigurationManager,
        TswIo.Hardware.Calibration.SessionSupervisor,
        TswIo.Firmware.UploadManager,
        TswIo.Train.Detection,
        TswIo.Train.Calibration.SessionSupervisor,
        # Start to serve requests, typically the last entry
        TswIoWeb.Endpoint
      ] ++ simulator_connection_child() ++ lever_controller_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TswIo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TswIoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # Skip migrations in dev/test (when not in a release).
    # Run migrations automatically when using a release (including Burrito desktop builds).
    # RELEASE_NAME is set by Mix releases, BURRITO is set by the Tauri sidecar launcher.
    System.get_env("RELEASE_NAME") == nil and System.get_env("BURRITO") == nil
  end

  # Returns the Simulator.Connection child spec only in non-test environments.
  # In test, this GenServer would interfere with the Ecto Sandbox since it
  # queries the database during initialization via AutoConfig.ensure_config/0.
  defp simulator_connection_child do
    if Application.get_env(:tsw_io, :start_simulator_connection, true) do
      [TswIo.Simulator.Connection]
    else
      []
    end
  end

  # Returns the LeverController child spec only in non-test environments.
  # In test, this GenServer subscribes to multiple pubsub topics and
  # interacts with other GenServers that may not be running.
  defp lever_controller_child do
    if Application.get_env(:tsw_io, :start_lever_controller, true) do
      [TswIo.Train.LeverController]
    else
      []
    end
  end
end
