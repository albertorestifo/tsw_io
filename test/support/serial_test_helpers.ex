defmodule TswIo.SerialTestHelpers do
  @moduledoc """
  Test helpers and builders for serial connection testing.
  """

  alias TswIo.Device
  alias TswIo.Serial.Connection.DeviceConnection
  alias TswIo.Serial.Connection.State

  @doc """
  Creates a DeviceConnection in :connecting state.

  ## Options
  - `:port` - Port name (default: "/dev/tty.test")
  - `:pid` - Process ID (default: self())
  """
  def build_connecting_connection(opts \\ []) do
    port = Keyword.get(opts, :port, "/dev/tty.test")
    pid = Keyword.get(opts, :pid, self())
    DeviceConnection.new(port, pid)
  end

  @doc """
  Creates a DeviceConnection in :discovering state.

  ## Options
  - `:port` - Port name (default: "/dev/tty.test")
  - `:pid` - Process ID (default: self())
  """
  def build_discovering_connection(opts \\ []) do
    opts
    |> build_connecting_connection()
    |> DeviceConnection.mark_discovering()
  end

  @doc """
  Creates a DeviceConnection in :connected state.

  ## Options
  - `:port` - Port name (default: "/dev/tty.test")
  - `:pid` - Process ID (default: self())
  - `:device` - Device struct (default: build_device())
  """
  def build_connected_connection(opts \\ []) do
    device = Keyword.get(opts, :device, build_device())

    opts
    |> build_discovering_connection()
    |> DeviceConnection.mark_connected(device)
  end

  @doc """
  Creates a DeviceConnection in :disconnecting state.

  ## Options
  - `:port` - Port name (default: "/dev/tty.test")
  - `:pid` - Process ID (default: self())
  - `:from_status` - Starting status (default: :connected)
  """
  def build_disconnecting_connection(opts \\ []) do
    from_status = Keyword.get(opts, :from_status, :connected)

    conn =
      case from_status do
        :connecting -> build_connecting_connection(opts)
        :discovering -> build_discovering_connection(opts)
        :connected -> build_connected_connection(opts)
      end

    DeviceConnection.mark_disconnecting(conn)
  end

  @doc """
  Creates a DeviceConnection in :failed state.

  ## Options
  - `:port` - Port name (default: "/dev/tty.test")
  - `:pid` - Process ID (default: nil)
  - `:failed_at` - Timestamp in milliseconds (default: current time)
  """
  def build_failed_connection(opts \\ []) do
    conn = build_disconnecting_connection(opts)
    failed_conn = DeviceConnection.mark_failed(conn)

    # Allow overriding failed_at for testing backoff logic
    case Keyword.get(opts, :failed_at) do
      nil -> failed_conn
      timestamp -> %{failed_conn | failed_at: timestamp}
    end
  end

  @doc """
  Creates a Device struct.

  ## Options
  - `:id` - Device ID (default: 1)
  - `:version` - Firmware version (default: 100)
  - `:config_id` - Configuration ID (default: nil)
  """
  def build_device(opts \\ []) do
    %Device{
      id: Keyword.get(opts, :id, 1),
      version: Keyword.get(opts, :version, 100),
      config_id: Keyword.get(opts, :config_id)
    }
  end

  @doc """
  Creates a Connection State with specified connections.

  ## Example
      iex> build_state([
      ...>   {"/dev/tty.test1", build_connected_connection(port: "/dev/tty.test1")},
      ...>   {"/dev/tty.test2", build_failed_connection(port: "/dev/tty.test2")}
      ...> ])
  """
  def build_state(connections \\ []) do
    ports =
      connections
      |> Enum.into(%{})

    %State{ports: ports}
  end

  @doc """
  Creates a pid for testing purposes.
  """
  def test_pid do
    spawn(fn -> :timer.sleep(:infinity) end)
  end

  @doc """
  Cleans up test processes.
  """
  def cleanup_pid(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
  end
end
