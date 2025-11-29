defmodule TswIo.Train.Calibration.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for spawning lever calibration sessions.

  Each calibration session runs as a separate process under this supervisor,
  allowing multiple levers to be calibrated concurrently if needed.
  """

  use DynamicSupervisor

  alias TswIo.Train.Calibration.LeverSession
  alias TswIo.Train.LeverConfig
  alias TswIo.Simulator.Client

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new calibration session for a lever.

  Returns `{:ok, pid}` if the session starts successfully,
  `{:error, :already_running}` if a session for this lever is already active.
  """
  @spec start_calibration(Client.t(), LeverConfig.t()) ::
          {:ok, pid()} | {:error, :already_running} | {:error, term()}
  def start_calibration(%Client{} = client, %LeverConfig{} = lever_config) do
    case get_session(lever_config.id) do
      nil ->
        child_spec = {LeverSession, {client, lever_config}}
        DynamicSupervisor.start_child(__MODULE__, child_spec)

      _pid ->
        {:error, :already_running}
    end
  end

  @doc """
  Stop a running calibration session.
  """
  @spec stop_calibration(integer()) :: :ok | {:error, :not_found}
  def stop_calibration(lever_config_id) do
    case get_session(lever_config_id) do
      nil ->
        {:error, :not_found}

      pid ->
        # Handle race condition where process terminates between check and terminate
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
        end
    end
  end

  @doc """
  Get the PID of a running calibration session for a lever config.
  """
  @spec get_session(integer()) :: pid() | nil
  def get_session(lever_config_id) do
    LeverSession.whereis(lever_config_id)
  end

  @doc """
  Check if a calibration session is running for a lever config.
  """
  @spec session_running?(integer()) :: boolean()
  def session_running?(lever_config_id) do
    get_session(lever_config_id) != nil
  end
end
