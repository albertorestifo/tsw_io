defmodule TswIo.Serial.Connection do
  @moduledoc """
  Manages connections to TWS devices over serial ports.

  Implements a state machine for each port's lifecycle, preventing race
  conditions between discovery, connection, and cleanup operations.
  """

  use GenServer

  alias Circuits.UART
  alias TswIo.Serial.Connection.DeviceConnection
  alias TswIo.Serial.Connection.State
  alias TswIo.Serial.Discovery
  alias TswIo.Serial.Framing

  require Logger

  # Retry failed ports after 30 seconds
  @failed_port_backoff_ms 30_000
  # Run discovery every second
  @discovery_interval_ms 1_000
  # Port name patterns to ignore (Bluetooth, debug consoles, etc.)
  @ignored_port_patterns [
    ~r/Bluetooth/i,
    ~r/debug/i,
    ~r/TONE/i
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @doc "Get all connected devices"
  @spec connected_devices() :: [DeviceConnection.t()]
  def connected_devices do
    GenServer.call(__MODULE__, :connected_devices)
  end

  # Server callbacks

  @impl true
  def init(%State{} = state) do
    schedule_discovery()
    {:ok, state}
  end

  @impl true
  def handle_call(:connected_devices, _from, state) do
    {:reply, State.connected_devices(state), state}
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
    Logger.info("Received data from port #{port}: #{inspect(data)}")
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

        {:noreply, updated_state}
    end
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
    {:noreply, updated_state}
  end

  # Private functions

  defp schedule_discovery do
    Process.send_after(self(), :discover, @discovery_interval_ms)
  end

  defp discover_new_ports(state) do
    UART.enumerate()
    |> Map.keys()
    |> Enum.filter(&should_connect?(&1, state))
    |> Enum.each(&GenServer.cast(__MODULE__, {:connect, &1}))
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

  defp ignored_port?(port) do
    Enum.any?(@ignored_port_patterns, &Regex.match?(&1, port))
  end

  defp find_port_by_pid(%State{ports: ports}, pid) do
    case Enum.find(ports, fn {_port, conn} -> conn.pid == pid end) do
      {port, _conn} -> port
      nil -> nil
    end
  end

  defp do_connect(port, state) do
    {:ok, pid} = UART.start_link()
    Process.monitor(pid)

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
    with {:ok, device} <- Discovery.discover(pid),
         :ok <- UART.configure(pid, active: true) do
      Logger.info("Discovered device #{inspect(device)} on port #{port}")
      updated_state = State.put(state, DeviceConnection.mark_connected(conn, device))
      {:noreply, updated_state}
    else
      {:error, reason} ->
        Logger.error("Failed to discover/configure device on port #{port}: #{inspect(reason)}")
        GenServer.cast(self(), {:disconnect, port})
        {:noreply, state}
    end
  end

  defp start_async_cleanup(port, pid) do
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
