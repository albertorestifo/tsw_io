defmodule TswIo.SerialTestHelpers do
  @moduledoc """
  Test helpers and builders for serial connection testing.
  """

  alias TswIo.Serial.Connection.DeviceConnection
  alias TswIo.Serial.Connection.State
  alias TswIo.Serial.Protocol.IdentityResponse

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
  - `:identity_response` - IdentityResponse struct (default: build_identity_response())
  """
  def build_connected_connection(opts \\ []) do
    identity_response = Keyword.get(opts, :identity_response, build_identity_response())

    opts
    |> build_discovering_connection()
    |> DeviceConnection.mark_connected(identity_response)
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
  Creates a DeviceConnection in :uploading state.

  ## Options
  - `:port` - Port name (default: "/dev/tty.test")
  """
  def build_uploading_connection(opts \\ []) do
    {conn, _token} =
      opts
      |> build_connected_connection()
      |> DeviceConnection.mark_uploading()

    conn
  end

  @doc """
  Creates an IdentityResponse struct.

  ## Options
  - `:request_id` - Request ID (default: 123)
  - `:version` - Firmware version as "MAJOR.MINOR.PATCH" (default: "1.0.0")
  - `:config_id` - Configuration ID (default: 0)
  """
  def build_identity_response(opts \\ []) do
    %IdentityResponse{
      request_id: Keyword.get(opts, :request_id, 123),
      version: Keyword.get(opts, :version, "1.0.0"),
      config_id: Keyword.get(opts, :config_id, 0)
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
