defmodule TswIo.Train.Detection do
  @moduledoc """
  Monitors the simulator for train changes and manages the active train configuration.

  Responsibilities:
  - Poll formation data periodically when connected to simulator
  - Derive train identifier from formation
  - Match identifier to stored train configurations
  - Broadcast train change events via PubSub

  ## Events

  Subscribers receive messages on "train:detection":
  - `{:train_detected, %{identifier: String.t(), train: Train.t() | nil}}`
  - `{:train_changed, Train.t() | nil}`
  - `{:detection_error, term()}`
  """

  use GenServer
  require Logger

  alias TswIo.Simulator.Connection, as: SimulatorConnection
  alias TswIo.Simulator.ConnectionState
  alias TswIo.Simulator.Client
  alias TswIo.Train
  alias TswIo.Train.Identifier

  @poll_interval_ms 5_000
  @pubsub_topic "train:detection"

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            active_train: Train.Train.t() | nil,
            current_identifier: String.t() | nil,
            last_check: DateTime.t() | nil,
            polling_enabled: boolean()
          }

    defstruct active_train: nil,
              current_identifier: nil,
              last_check: nil,
              polling_enabled: false
  end

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Subscribe to train detection events.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(TswIo.PubSub, @pubsub_topic)
  end

  @doc """
  Get the currently active train.
  """
  @spec get_active_train() :: Train.Train.t() | nil
  def get_active_train do
    GenServer.call(__MODULE__, :get_active_train)
  end

  @doc """
  Get the current train identifier.
  """
  @spec get_current_identifier() :: String.t() | nil
  def get_current_identifier do
    GenServer.call(__MODULE__, :get_current_identifier)
  end

  @doc """
  Get the current detection state.
  """
  @spec get_state() :: State.t()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Manually trigger train detection sync.
  """
  @spec sync() :: :ok
  def sync do
    GenServer.cast(__MODULE__, :sync)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    # Subscribe to simulator connection changes
    SimulatorConnection.subscribe()

    # Check initial connection status
    send(self(), :check_connection)

    {:ok, %State{}}
  end

  @impl true
  def handle_call(:get_active_train, _from, %State{} = state) do
    {:reply, state.active_train, state}
  end

  @impl true
  def handle_call(:get_current_identifier, _from, %State{} = state) do
    {:reply, state.current_identifier, state}
  end

  @impl true
  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:sync, %State{} = state) do
    new_state = detect_train(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_connection, %State{} = state) do
    case get_simulator_status() do
      %ConnectionState{status: :connected} ->
        schedule_poll()
        {:noreply, %{state | polling_enabled: true}}

      _ ->
        {:noreply, %{state | polling_enabled: false}}
    end
  end

  @impl true
  def handle_info(:poll, %State{polling_enabled: true} = state) do
    new_state = detect_train(state)
    schedule_poll()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll, %State{polling_enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:simulator_status_changed, %ConnectionState{status: :connected}},
        %State{} = state
      ) do
    Logger.info("Simulator connected, enabling train detection polling")
    schedule_poll()
    new_state = %{state | polling_enabled: true}
    # Trigger immediate detection
    send(self(), :poll)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:simulator_status_changed, %ConnectionState{}}, %State{} = state) do
    Logger.info("Simulator disconnected, disabling train detection polling")
    new_state = %{state | polling_enabled: false, active_train: nil, current_identifier: nil}
    broadcast({:train_changed, nil})
    {:noreply, new_state}
  end

  # Private Functions

  defp detect_train(%State{} = state) do
    case get_simulator_status() do
      %ConnectionState{status: :connected, client: %Client{} = client} ->
        do_detect_train(state, client)

      _ ->
        state
    end
  end

  defp do_detect_train(%State{} = state, %Client{} = client) do
    case Identifier.derive_from_formation(client) do
      {:ok, identifier} ->
        handle_identifier_detected(state, identifier)

      {:error, reason} ->
        Logger.warning("Failed to detect train: #{inspect(reason)}")
        broadcast({:detection_error, reason})
        state
    end
  end

  defp handle_identifier_detected(%State{current_identifier: identifier} = state, identifier) do
    # Same train, no change - just update last_check
    %{state | last_check: DateTime.utc_now()}
  end

  defp handle_identifier_detected(%State{} = state, identifier) do
    # Different train detected
    Logger.info("Train identifier changed: #{identifier}")

    train =
      case Train.get_train_by_identifier(identifier) do
        {:ok, train} -> train
        {:error, :not_found} -> nil
      end

    broadcast({:train_detected, %{identifier: identifier, train: train}})

    if state.active_train != train do
      broadcast({:train_changed, train})
    end

    %{state | current_identifier: identifier, active_train: train, last_check: DateTime.utc_now()}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(TswIo.PubSub, @pubsub_topic, message)
  end

  # Safely get simulator status, handling the case where SimulatorConnection
  # is not running (e.g., in test environment)
  defp get_simulator_status do
    if Process.whereis(SimulatorConnection) do
      SimulatorConnection.get_status()
    else
      %ConnectionState{status: :disconnected}
    end
  end
end
