defmodule TswIo.Train.Calibration.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for spawning lever calibration sessions.

  Each calibration session runs as a separate process under this supervisor,
  allowing multiple levers to be calibrated concurrently if needed.

  Supports two types of sessions:
  - **LeverSession**: Auto-detects notches from simulator API
  - **NotchMappingSession**: Guided wizard for mapping physical input positions to notch boundaries
  """

  use DynamicSupervisor

  alias TswIo.Train.Calibration.LeverSession
  alias TswIo.Train.Calibration.NotchMappingSession
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
  Start a notch mapping session for guided input-to-notch boundary mapping.

  ## Options

    * `:lever_config` - Required. The lever config with preloaded notches.
    * `:port` - Required. The serial port of the bound device.
    * `:pin` - Required. The pin number of the bound input.
    * `:calibration` - Required. The input's calibration data.

  Returns `{:ok, pid}` if the session starts successfully,
  `{:error, :already_running}` if a mapping session for this lever is already active.
  """
  @spec start_notch_mapping(keyword()) ::
          {:ok, pid()} | {:error, :already_running} | {:error, term()}
  def start_notch_mapping(opts) do
    lever_config = Keyword.fetch!(opts, :lever_config)

    case get_notch_mapping_session(lever_config.id) do
      nil ->
        child_spec = {NotchMappingSession, opts}
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
  Stop a running notch mapping session.
  """
  @spec stop_notch_mapping(integer()) :: :ok | {:error, :not_found}
  def stop_notch_mapping(lever_config_id) do
    case get_notch_mapping_session(lever_config_id) do
      nil ->
        {:error, :not_found}

      pid ->
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
  Get the PID of a running notch mapping session for a lever config.
  """
  @spec get_notch_mapping_session(integer()) :: pid() | nil
  def get_notch_mapping_session(lever_config_id) do
    NotchMappingSession.whereis(lever_config_id)
  end

  @doc """
  Check if a calibration session is running for a lever config.
  """
  @spec session_running?(integer()) :: boolean()
  def session_running?(lever_config_id) do
    get_session(lever_config_id) != nil
  end

  @doc """
  Check if a notch mapping session is running for a lever config.
  """
  @spec notch_mapping_running?(integer()) :: boolean()
  def notch_mapping_running?(lever_config_id) do
    get_notch_mapping_session(lever_config_id) != nil
  end
end
