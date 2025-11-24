defmodule TswIo.Serial.Connection do
  @moduledoc """
  Hols the pool of connection processes to TWS devices that have been identified.
  """

  use GenServer

  alias Circuits.UART
  alias TswIo.Serial.Connection.DeviceConnection
  alias TswIo.Serial.Connection.State
  alias TswIo.Serial.Discovery
  alias TswIo.Serial.Framing

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @impl true
  def init(%State{} = state) do
    schedule_discovery()
    {:ok, state}
  end

  @impl true
  def handle_info(:discover, %State{} = state) do
    UART.enumerate()
    |> Map.keys()
    |> Enum.reject(&connected?(&1, state))
    |> Enum.each(fn port -> GenServer.cast(__MODULE__, {:connect, port}) end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, port, data}, %State{} = state) do
    Logger.info("Received data from port #{port}: #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, port, {:error, reason}}, %State{} = state) do
    Logger.error("Error on port #{port}: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:connect, port}, %State{} = state) do
    {:ok, pid} = UART.start_link()

    case UART.open(pid, port,
           active: false,
           speed: 115_200,
           framing: Framing,
           rx_framing_timeout: 1_000
         ) do
      :ok ->
        Logger.info("Connected to device on port #{port}")
        GenServer.cast(self(), {:check_device, port})

        {:noreply,
         %State{
           devices: [%DeviceConnection{port: port, pid: pid, device: nil} | state.devices]
         }}

      {:error, reason} ->
        Logger.error("Failed to open port #{port}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:check_device, port}, %State{devices: devices} = state) do
    with %DeviceConnection{pid: pid} <- Enum.find(devices, &matching_port(&1, port)),
         {:ok, device} <- Discovery.discover(pid),
         :ok <- UART.configure(pid, active: true) do
      Logger.info("Discovered device #{inspect(device)} on port #{port}")

      updated_devices =
        Enum.map(devices, fn
          %DeviceConnection{port: ^port} = dc -> %DeviceConnection{dc | device: device}
          dc -> dc
        end)

      {:noreply, %State{devices: updated_devices}}
    else
      nil ->
        Logger.warning("No connection found for port #{port} during device check")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to discover device on port #{port}: #{inspect(reason)}")
        GenServer.cast(self(), {:disconnect, port})
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:disconnect, port}, %State{devices: devices} = state) do
    with %DeviceConnection{pid: pid} <- Enum.find(devices, &matching_port(&1, port)),
         :ok <- UART.close(pid) do
      Logger.info("Disconnected device on port #{port}")
      {:noreply, %State{devices: Enum.reject(devices, &matching_port(&1, port))}}
    else
      nil ->
        Logger.warning("No device connected on port #{port}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to close port #{port}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp schedule_discovery() do
    Process.send_after(self(), :discover, 1_000)
  end

  # Check if the given port is already connected
  defp connected?(port, %State{devices: devices}) do
    Enum.any?(devices, &matching_port(&1, port))
  end

  defp matching_port(%DeviceConnection{port: port}, target_port) do
    port == target_port
  end
end
