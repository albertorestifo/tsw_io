defmodule TswIo.Serial.Connection do
  @moduledoc """
  Manages connections to tsw_io devices over serial ports.

  Implements a state machine for each port's lifecycle, preventing race
  conditions between discovery, connection, and cleanup operations.
  """

  use GenServer

  alias Circuits.UART
  alias TswIo.Serial.Connection.DeviceConnection
  alias TswIo.Serial.Connection.State
  alias TswIo.Serial.Discovery
  alias TswIo.Serial.Framing
  alias TswIo.Serial.Protocol.Message

  require Logger

  # Retry failed ports after 30 seconds
  @failed_port_backoff_ms 30_000
  # Run discovery every minute
  @discovery_interval_ms 60_000
  # Timeout for cleanup operations (failsafe if task crashes)
  @cleanup_timeout_ms 5_000
  # Timeout for discovery operations
  @discovery_timeout_ms 5_000
  # Port name patterns to ignore (Bluetooth, debug consoles, etc.)
  @ignored_port_patterns [
    ~r/Bluetooth/i,
    ~r/debug/i,
    ~r/TONE/i
  ]

  @pubsub_topic "device_updates"
  @serial_messages_topic "serial:messages"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @doc "Get all connected devices"
  @spec connected_devices() :: [DeviceConnection.t()]
  def connected_devices do
    GenServer.call(__MODULE__, :connected_devices)
  end

  @doc "Get all tracked devices (any status)"
  @spec list_devices() :: [DeviceConnection.t()]
  def list_devices do
    GenServer.call(__MODULE__, :list_devices)
  end

  @doc "Get all available serial ports (filtered by ignored patterns)"
  @spec enumerate_ports() :: [String.t()]
  def enumerate_ports do
    UART.enumerate()
    |> Map.keys()
    |> Enum.reject(&ignored_port?/1)
    |> Enum.sort()
  end

  defp ignored_port?(port) do
    Enum.any?(@ignored_port_patterns, &Regex.match?(&1, port))
  end

  @doc "Trigger an immediate device scan"
  @spec scan() :: :ok
  def scan do
    GenServer.cast(__MODULE__, :scan)
  end

  @doc "Disconnect a specific device by port"
  @spec disconnect(String.t()) :: :ok
  def disconnect(port) do
    GenServer.cast(__MODULE__, {:disconnect, port})
  end

  @doc "Subscribe to device update events"
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(TswIo.PubSub, @pubsub_topic)
  end

  @doc "Subscribe to serial messages from a specific port"
  @spec subscribe_messages(String.t()) :: :ok | {:error, term()}
  def subscribe_messages(port) do
    Phoenix.PubSub.subscribe(TswIo.PubSub, "#{@serial_messages_topic}:#{port}")
  end

  @doc """
  Send a message to a device on the specified port.

  The message must implement the Message behaviour and will be encoded
  before sending over the serial connection.
  """
  @spec send_message(String.t(), Message.t()) :: :ok | {:error, term()}
  def send_message(port, message) do
    GenServer.call(__MODULE__, {:send_message, port, message})
  end

  @doc """
  Request exclusive access to a port for firmware upload.

  Closes the UART connection and marks the device as uploading.
  Returns a token that must be used to release the port.

  ## Returns

    * `{:ok, token}` - Port is now available for avrdude
    * `{:error, :device_not_found}` - Port not tracked
    * `{:error, :not_connected}` - Device not in connected state
    * `{:error, :upload_in_progress}` - Another upload is already in progress
  """
  @spec request_upload_access(String.t()) ::
          {:ok, String.t()} | {:error, :device_not_found | :not_connected | :upload_in_progress}
  def request_upload_access(port) do
    GenServer.call(__MODULE__, {:request_upload_access, port})
  end

  @doc """
  Release upload access and allow reconnection.

  The port will be rediscovered on the next scan cycle.

  ## Returns

    * `:ok` - Port released successfully
    * `{:error, :invalid_token}` - Token doesn't match
  """
  @spec release_upload_access(String.t(), String.t()) :: :ok | {:error, :invalid_token}
  def release_upload_access(port, token) do
    GenServer.call(__MODULE__, {:release_upload_access, port, token})
  end

  # Server callbacks

  @impl true
  def init(%State{} = state) do
    # Start with a quick discovery to get things going
    schedule_discovery(1_000)
    {:ok, state}
  end

  @impl true
  def handle_call(:connected_devices, _from, state) do
    {:reply, State.connected_devices(state), state}
  end

  @impl true
  def handle_call(:list_devices, _from, %State{ports: ports} = state) do
    {:reply, Map.values(ports), state}
  end

  @impl true
  def handle_call({:send_message, port, message}, _from, state) do
    case State.get(state, port) do
      %DeviceConnection{status: :connected, pid: pid} ->
        # Get the module that implements the Message behaviour for encoding
        module = message.__struct__

        case module.encode(message) do
          {:ok, encoded} ->
            result = UART.write(pid, encoded)
            {:reply, result, state}

          {:error, reason} ->
            {:reply, {:error, {:encode_failed, reason}}, state}
        end

      %DeviceConnection{status: status} ->
        {:reply, {:error, {:not_connected, status}}, state}

      nil ->
        {:reply, {:error, :unknown_port}, state}
    end
  end

  @impl true
  def handle_call({:request_upload_access, port}, _from, state) do
    # Check if any device is already uploading
    has_upload_in_progress =
      state.ports
      |> Map.values()
      |> Enum.any?(&(&1.status == :uploading))

    if has_upload_in_progress do
      {:reply, {:error, :upload_in_progress}, state}
    else
      case State.get(state, port) do
        nil ->
          {:reply, {:error, :device_not_found}, state}

        %DeviceConnection{status: :connected, pid: pid} = conn ->
          # Close the UART connection synchronously
          safe_close_uart(pid)
          # Mark as uploading and get token
          {updated_conn, token} = DeviceConnection.mark_uploading(conn)
          updated_state = State.put(state, updated_conn)
          broadcast_update(updated_state)
          {:reply, {:ok, token}, updated_state}

        %DeviceConnection{status: _status} ->
          {:reply, {:error, :not_connected}, state}
      end
    end
  end

  @impl true
  def handle_call({:release_upload_access, port, token}, _from, state) do
    case State.get(state, port) do
      %DeviceConnection{status: :uploading} = conn ->
        case DeviceConnection.release_upload(conn, token) do
          {:ok, updated_conn} ->
            updated_state = State.put(state, updated_conn)
            broadcast_update(updated_state)
            {:reply, :ok, updated_state}

          {:error, :invalid_token} ->
            {:reply, {:error, :invalid_token}, state}
        end

      _ ->
        {:reply, {:error, :invalid_token}, state}
    end
  end

  @impl true
  def handle_cast(:scan, state) do
    discover_new_ports(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:connect, port}, state) do
    # Double-check we should still connect (state may have changed)
    if should_connect?(port, state) do
      do_connect(port, state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:check_device, port}, state) do
    case State.get(state, port) do
      %DeviceConnection{status: :discovering, pid: pid} = conn ->
        do_discover(conn, pid, state)

      _ ->
        # Port no longer in discovering state, ignore
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:disconnect, port}, state) do
    case State.get(state, port) do
      conn when is_nil(conn) or conn.status in [:disconnecting, :failed] ->
        # Not tracked or already cleaning up
        {:noreply, state}

      %DeviceConnection{pid: pid} = conn ->
        updated_state = State.put(state, DeviceConnection.mark_disconnecting(conn))
        start_async_cleanup(port, pid)
        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_cast({:cleanup_complete, port}, state) do
    updated_state =
      State.update(state, port, fn conn ->
        DeviceConnection.mark_failed(conn)
      end)

    Logger.debug("Cleanup complete for port #{port}")
    broadcast_update(updated_state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:discover, %State{} = state) do
    discover_new_ports(state)
    schedule_discovery()
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, port, {:error, reason}}, state) do
    Logger.error("Error on port #{port}: #{inspect(reason)}")
    GenServer.cast(self(), {:disconnect, port})
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, port, data}, state) do
    case Message.decode(data) do
      {:ok, message} ->
        # Logger.debug("Received message from port #{port}: #{inspect(message)}")
        broadcast_message(port, message)

      {:error, reason} ->
        Logger.warning("Failed to decode message from port #{port}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case find_port_by_pid(state, pid) do
      nil ->
        {:noreply, state}

      port ->
        Logger.warning("UART process for port #{port} died: #{inspect(reason)}")
        # Mark as failed directly since the process is already dead
        updated_state =
          State.update(state, port, fn conn ->
            conn
            |> DeviceConnection.mark_disconnecting()
            |> DeviceConnection.mark_failed()
          end)

        broadcast_update(updated_state)
        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:cleanup_timeout, port}, state) do
    case State.get(state, port) do
      %DeviceConnection{status: :disconnecting} = conn ->
        Logger.warning("Cleanup timeout for port #{port}, forcing to failed state")
        updated_state = State.put(state, DeviceConnection.mark_failed(conn))
        broadcast_update(updated_state)
        {:noreply, updated_state}

      _ ->
        # Already completed or no longer tracked
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:discovery_timeout, port}, state) do
    case State.get(state, port) do
      %DeviceConnection{status: :discovering} ->
        Logger.warning("Discovery timeout for port #{port}")
        GenServer.cast(self(), {:disconnect, port})
        {:noreply, state}

      _ ->
        # Already progressed past discovering
        {:noreply, state}
    end
  end

  defp schedule_discovery(interval_ms \\ @discovery_interval_ms) do
    Process.send_after(self(), :discover, interval_ms)
  end

  defp broadcast_update(state) do
    devices = Map.values(state.ports)
    Phoenix.PubSub.broadcast(TswIo.PubSub, @pubsub_topic, {:devices_updated, devices})
  end

  defp broadcast_message(port, message) do
    Phoenix.PubSub.broadcast(
      TswIo.PubSub,
      "#{@serial_messages_topic}:#{port}",
      {:serial_message, port, message}
    )
  end

  defp discover_new_ports(state) do
    all_ports = Map.keys(UART.enumerate())
    eligible_ports = Enum.filter(all_ports, &should_connect?(&1, state))

    Logger.debug(
      "Discovery: found #{length(all_ports)} ports, #{length(eligible_ports)} eligible"
    )

    Enum.each(eligible_ports, &GenServer.cast(__MODULE__, {:connect, &1}))
  end

  defp should_connect?(port, state) do
    not ignored_port?(port) and
      case State.get(state, port) do
        # Not tracked, should connect
        nil -> true
        # Failed and backoff expired, should retry
        conn -> DeviceConnection.should_retry?(conn, @failed_port_backoff_ms)
      end
  end

  defp find_port_by_pid(%State{ports: ports}, pid) do
    case Enum.find(ports, fn {_port, conn} -> conn.pid == pid end) do
      {port, _conn} -> port
      nil -> nil
    end
  end

  defp do_connect(port, state) do
    case UART.start_link() do
      {:ok, pid} ->
        Process.monitor(pid)
        do_open_port(port, pid, state)

      {:error, reason} ->
        Logger.error("Failed to start UART process for port #{port}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp do_open_port(port, pid, state) do
    # Track immediately in :connecting state
    conn = DeviceConnection.new(port, pid)
    state_with_conn = State.put(state, conn)

    case UART.open(pid, port,
           active: false,
           speed: 115_200,
           framing: Framing,
           rx_framing_timeout: 1_000
         ) do
      :ok ->
        Logger.info("Connected to device on port #{port}")
        updated_state = State.update(state_with_conn, port, &DeviceConnection.mark_discovering/1)
        # Schedule discovery timeout failsafe
        Process.send_after(self(), {:discovery_timeout, port}, @discovery_timeout_ms)
        GenServer.cast(self(), {:check_device, port})
        {:noreply, updated_state}

      {:error, reason} ->
        Logger.error("Failed to open port #{port}: #{inspect(reason)}")
        # Mark as disconnecting and cleanup
        updated_state =
          State.update(state_with_conn, port, &DeviceConnection.mark_disconnecting/1)

        start_async_cleanup(port, pid)
        {:noreply, updated_state}
    end
  end

  defp do_discover(%DeviceConnection{port: port} = conn, pid, state) do
    with {:ok, identity} <- Discovery.discover(pid),
         :ok <- UART.configure(pid, active: true) do
      Logger.info("Discovered device #{inspect(identity)} on port #{port}")
      updated_state = State.put(state, DeviceConnection.mark_connected(conn, identity))
      broadcast_update(updated_state)
      {:noreply, updated_state}
    else
      {:error, reason} ->
        Logger.error("Failed to discover/configure device on port #{port}: #{inspect(reason)}")
        GenServer.cast(self(), {:disconnect, port})
        {:noreply, state}
    end
  end

  defp start_async_cleanup(port, pid) do
    # Schedule a failsafe timeout in case the task crashes
    Process.send_after(self(), {:cleanup_timeout, port}, @cleanup_timeout_ms)

    Task.start(fn ->
      try do
        safe_stop_uart(pid)
      catch
        kind, reason ->
          Logger.debug("Cleanup error for #{port}: #{kind} #{inspect(reason)}")
      end

      # Always notify completion, even if cleanup had errors
      GenServer.cast(__MODULE__, {:cleanup_complete, port})
    end)
  end

  # Safely closes a UART connection for firmware upload.
  # Only closes the port, doesn't stop the GenServer process.
  defp safe_close_uart(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        UART.close(pid)
        GenServer.stop(pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  # Safely stops a UART process, handling unresponsive or dead processes.
  # May raise if the UART process is in a bad state - caller should handle.
  defp safe_stop_uart(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        case UART.close(pid) do
          :ok -> :ok
          {:error, _} -> force_stop(pid)
        end
      catch
        :exit, _ -> force_stop(pid)
      end
    else
      :ok
    end
  end

  defp force_stop(pid) do
    try do
      GenServer.stop(pid, :normal, 100)
    catch
      :exit, _ ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
    end

    :ok
  end
end
