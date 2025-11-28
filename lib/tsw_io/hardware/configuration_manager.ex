defmodule TswIo.Hardware.ConfigurationManager do
  @moduledoc """
  Manages device configuration lifecycle and coordinates between
  the Hardware context and Serial layer.

  Responsibilities:
  - Apply configurations to devices
  - Track in-flight configuration operations
  - Handle async responses (ConfigurationStored, ConfigurationError)
  - Broadcast configuration events to UI
  - Manage configuration timeouts
  - Store and broadcast input values
  """

  use GenServer

  alias TswIo.Hardware
  alias TswIo.Hardware.Input
  alias TswIo.Serial.Connection
  alias TswIo.Serial.Protocol.Configure
  alias TswIo.Serial.Protocol.ConfigurationStored
  alias TswIo.Serial.Protocol.ConfigurationError
  alias TswIo.Serial.Protocol.InputValue

  require Logger

  @config_timeout_ms 10_000
  @config_topic "hardware:configuration"
  @input_values_topic "hardware:input_values"

  defmodule State do
    @moduledoc false

    @type in_flight_info :: %{
            port: String.t(),
            timer_ref: reference(),
            device_id: integer()
          }

    @type t :: %__MODULE__{
            in_flight: %{integer() => in_flight_info()},
            input_values: %{String.t() => %{integer() => integer()}},
            subscribed_ports: MapSet.t(String.t())
          }

    defstruct in_flight: %{},
              input_values: %{},
              subscribed_ports: MapSet.new()
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %State{}, Keyword.merge([name: __MODULE__], opts))
  end

  @doc """
  Apply a configuration to a device.

  This generates a config_id, sends Configure messages to the device,
  and tracks the operation until ConfigurationStored or timeout.

  Returns `{:ok, config_id}` immediately - subscribe to events for completion.
  """
  @spec apply_configuration(String.t(), integer()) :: {:ok, integer()} | {:error, term()}
  def apply_configuration(port, device_id) do
    GenServer.call(__MODULE__, {:apply_configuration, port, device_id})
  end

  @doc "Subscribe to configuration events (for LiveView)"
  @spec subscribe_configuration() :: :ok | {:error, term()}
  def subscribe_configuration do
    Phoenix.PubSub.subscribe(TswIo.PubSub, @config_topic)
  end

  @doc "Subscribe to input value updates for a specific port"
  @spec subscribe_input_values(String.t()) :: :ok | {:error, term()}
  def subscribe_input_values(port) do
    Phoenix.PubSub.subscribe(TswIo.PubSub, "#{@input_values_topic}:#{port}")
  end

  @doc "Get current input values for a port"
  @spec get_input_values(String.t()) :: %{integer() => integer()}
  def get_input_values(port) do
    GenServer.call(__MODULE__, {:get_input_values, port})
  end

  # Server callbacks

  @impl true
  def init(%State{} = state) do
    # Subscribe to device updates to track connections
    Connection.subscribe()
    {:ok, state}
  end

  @impl true
  def handle_call({:apply_configuration, port, device_id}, _from, %State{} = state) do
    # Subscribe to messages from this port if not already subscribed
    state = maybe_subscribe_to_port(state, port)

    case do_apply_configuration(port, device_id, state) do
      {:ok, config_id, new_state} ->
        {:reply, {:ok, config_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_input_values, port}, _from, %State{} = state) do
    values = Map.get(state.input_values, port, %{})
    {:reply, values, state}
  end

  @impl true
  def handle_info({:devices_updated, devices}, %State{} = state) do
    # Clear input values for disconnected devices
    connected_ports = MapSet.new(devices, & &1.port)

    new_input_values =
      Map.filter(state.input_values, fn {port, _} ->
        MapSet.member?(connected_ports, port)
      end)

    {:noreply, %{state | input_values: new_input_values}}
  end

  @impl true
  def handle_info(
        {:serial_message, port, %ConfigurationStored{config_id: config_id}},
        %State{} = state
      ) do
    case Map.pop(state.in_flight, config_id) do
      {nil, _} ->
        {:noreply, state}

      {%{timer_ref: timer_ref, device_id: device_id}, new_in_flight} ->
        Process.cancel_timer(timer_ref)

        case Hardware.confirm_configuration(device_id, config_id) do
          {:ok, device} ->
            Logger.info("Configuration #{config_id} successfully stored on device")
            broadcast_config_event({:configuration_applied, port, device, config_id})
            {:noreply, %{state | in_flight: new_in_flight}}

          {:error, reason} ->
            Logger.error("Failed to update device with config_id: #{inspect(reason)}")
            broadcast_config_event({:configuration_failed, port, device_id, reason})
            {:noreply, %{state | in_flight: new_in_flight}}
        end
    end
  end

  @impl true
  def handle_info(
        {:serial_message, port, %ConfigurationError{config_id: config_id}},
        %State{} = state
      ) do
    case Map.pop(state.in_flight, config_id) do
      {nil, _} ->
        {:noreply, state}

      {%{timer_ref: timer_ref, device_id: device_id}, new_in_flight} ->
        Process.cancel_timer(timer_ref)
        Logger.error("Configuration #{config_id} rejected by device")
        broadcast_config_event({:configuration_failed, port, device_id, :device_rejected})
        {:noreply, %{state | in_flight: new_in_flight}}
    end
  end

  @impl true
  def handle_info({:serial_message, port, %InputValue{pin: pin, value: value}}, %State{} = state) do
    port_values = Map.get(state.input_values, port, %{})
    updated_values = Map.put(port_values, pin, value)
    new_input_values = Map.put(state.input_values, port, updated_values)

    Phoenix.PubSub.broadcast(
      TswIo.PubSub,
      "#{@input_values_topic}:#{port}",
      {:input_value_updated, port, pin, value}
    )

    {:noreply, %{state | input_values: new_input_values}}
  end

  @impl true
  def handle_info({:serial_message, _port, _other_message}, %State{} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:config_timeout, config_id}, %State{} = state) do
    case Map.pop(state.in_flight, config_id) do
      {nil, _} ->
        {:noreply, state}

      {%{port: port, device_id: device_id}, new_in_flight} ->
        Logger.error("Configuration #{config_id} timed out")
        broadcast_config_event({:configuration_failed, port, device_id, :timeout})
        {:noreply, %{state | in_flight: new_in_flight}}
    end
  end

  # Private helpers

  defp maybe_subscribe_to_port(%State{} = state, port) do
    if MapSet.member?(state.subscribed_ports, port) do
      state
    else
      Connection.subscribe_messages(port)
      %{state | subscribed_ports: MapSet.put(state.subscribed_ports, port)}
    end
  end

  defp do_apply_configuration(port, device_id, %State{} = state) do
    with {:ok, _device} <- Hardware.get_device(device_id),
         {:ok, inputs} <- Hardware.list_inputs(device_id),
         :ok <- validate_inputs(inputs),
         {:ok, config_id} <- Hardware.generate_config_id(),
         :ok <- send_configuration_messages(port, config_id, inputs) do
      timer_ref = Process.send_after(self(), {:config_timeout, config_id}, @config_timeout_ms)

      in_flight_info = %{
        port: port,
        timer_ref: timer_ref,
        device_id: device_id
      }

      new_in_flight = Map.put(state.in_flight, config_id, in_flight_info)
      {:ok, config_id, %{state | in_flight: new_in_flight}}
    end
  end

  defp validate_inputs([]), do: {:error, :no_inputs}
  defp validate_inputs(_inputs), do: :ok

  defp send_configuration_messages(port, config_id, inputs) do
    total_parts = length(inputs)

    inputs
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {%Input{} = input, index}, :ok ->
      message = %Configure{
        config_id: config_id,
        total_parts: total_parts,
        part_number: index,
        input_type: input.input_type,
        pin: input.pin,
        sensitivity: input.sensitivity
      }

      case Connection.send_message(port, message) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp broadcast_config_event(event) do
    Phoenix.PubSub.broadcast(TswIo.PubSub, @config_topic, event)
  end
end
