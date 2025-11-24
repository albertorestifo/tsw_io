defmodule TswIo.Serial.Connection.DeviceConnection do
  @moduledoc """
  Represents a serial port in any lifecycle state.

  ## Lifecycle States

      :connecting → :discovering → :connected
           ↓             ↓              ↓
           └─────→ :disconnecting ←─────┘
                         ↓
                      :failed

  - `:connecting` - UART process started, attempting to open port
  - `:discovering` - Port open, sending identity request
  - `:connected` - Device identified and ready for use
  - `:disconnecting` - Cleanup in progress (async)
  - `:failed` - Cleanup complete, port will be retried after backoff
  """

  alias TswIo.Device

  @type status :: :connecting | :discovering | :connected | :disconnecting | :failed

  @type t :: %__MODULE__{
          port: String.t(),
          status: status(),
          pid: pid() | nil,
          device: Device.t() | nil,
          failed_at: integer() | nil
        }

  @enforce_keys [:port, :status]
  defstruct [:port, :status, :pid, :device, :failed_at]

  @doc "Create a new connection in :connecting state"
  @spec new(String.t(), pid()) :: t()
  def new(port, pid) do
    %__MODULE__{port: port, status: :connecting, pid: pid}
  end

  @doc "Transition to :discovering state after port opened successfully"
  @spec mark_discovering(t()) :: t()
  def mark_discovering(%__MODULE__{status: :connecting} = conn) do
    %__MODULE__{conn | status: :discovering}
  end

  @doc "Transition to :connected state with discovered device"
  @spec mark_connected(t(), Device.t()) :: t()
  def mark_connected(%__MODULE__{status: :discovering} = conn, device) do
    %__MODULE__{conn | status: :connected, device: device}
  end

  @doc """
  Transition to :disconnecting state (cleanup starting).

  Idempotent: no-op if already :disconnecting or :failed.
  """
  @spec mark_disconnecting(t()) :: t()
  def mark_disconnecting(%__MODULE__{status: status} = conn)
      when status in [:disconnecting, :failed] do
    conn
  end

  def mark_disconnecting(%__MODULE__{} = conn) do
    %__MODULE__{conn | status: :disconnecting}
  end

  @doc """
  Transition to :failed state (cleanup complete).

  Idempotent: no-op if already :failed (preserves original failed_at timestamp).
  """
  @spec mark_failed(t()) :: t()
  def mark_failed(%__MODULE__{status: :failed} = conn) do
    # Already failed, don't reset the timestamp
    conn
  end

  def mark_failed(%__MODULE__{status: :disconnecting} = conn) do
    %__MODULE__{conn | status: :failed, pid: nil, failed_at: System.monotonic_time(:millisecond)}
  end

  @doc "Check if port should be retried (failed long enough ago)"
  @spec should_retry?(t(), integer()) :: boolean()
  def should_retry?(%__MODULE__{status: :failed, failed_at: failed_at}, backoff_ms)
      when is_integer(failed_at) do
    System.monotonic_time(:millisecond) - failed_at >= backoff_ms
  end

  def should_retry?(%__MODULE__{}, _backoff_ms), do: false

  @doc "Check if this connection is actively using the port"
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}) do
    status in [:connecting, :discovering, :connected, :disconnecting]
  end
end
