defmodule TswIo.Serial.Connection.DeviceConnection do
  @moduledoc """
  Represents a serial port in any lifecycle state.

  ## Lifecycle States

      :connecting → :discovering → :connected → :uploading
           ↓             ↓              ↓            ↓
           └─────→ :disconnecting ←─────┴────────────┘
                         ↓
                      :failed

  - `:connecting` - UART process started, attempting to open port
  - `:discovering` - Port open, sending identity request
  - `:connected` - Device identified and ready for use
  - `:uploading` - Device disconnected for firmware upload via avrdude
  - `:disconnecting` - Cleanup in progress (async)
  - `:failed` - Cleanup complete, port will be retried after backoff
  """

  alias TswIo.Serial.Protocol.IdentityResponse

  @type status :: :connecting | :discovering | :connected | :uploading | :disconnecting | :failed

  @type t :: %__MODULE__{
          port: String.t(),
          status: status(),
          pid: pid() | nil,
          failed_at: integer() | nil,
          device_config_id: integer() | nil,
          device_version: String.t() | nil,
          upload_token: String.t() | nil,
          error_reason: String.t() | nil
        }

  @enforce_keys [:port, :status]
  defstruct [
    :port,
    :status,
    :pid,
    :device_config_id,
    :device_version,
    :failed_at,
    :upload_token,
    :error_reason
  ]

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
  @spec mark_connected(t(), IdentityResponse.t()) :: t()
  def mark_connected(%__MODULE__{status: :discovering} = conn, %IdentityResponse{
        config_id: config_id,
        version: version
      }) do
    %__MODULE__{conn | status: :connected, device_config_id: config_id, device_version: version}
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

  @doc "Mark as failed with an error reason"
  @spec mark_failed_with_reason(t(), String.t()) :: t()
  def mark_failed_with_reason(%__MODULE__{} = conn, reason) when is_binary(reason) do
    conn
    |> mark_disconnecting()
    |> mark_failed()
    |> Map.put(:error_reason, reason)
  end

  @doc "Set error reason on an existing connection"
  @spec set_error_reason(t(), term()) :: t()
  def set_error_reason(%__MODULE__{} = conn, reason) do
    %__MODULE__{conn | error_reason: format_error_reason(reason)}
  end

  @doc "Clear error reason (e.g., when retrying)"
  @spec clear_error(t()) :: t()
  def clear_error(%__MODULE__{} = conn) do
    %__MODULE__{conn | error_reason: nil}
  end

  # Format various error types into human-readable strings
  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp format_error_reason(:eacces), do: "Permission denied"
  defp format_error_reason(:enoent), do: "Port not found"
  defp format_error_reason(:ebusy), do: "Port is busy (in use by another program)"
  defp format_error_reason(:eagain), do: "Resource temporarily unavailable"
  defp format_error_reason(:eio), do: "I/O error"
  defp format_error_reason(:einval), do: "Invalid port configuration"
  defp format_error_reason(:enxio), do: "Device not configured"
  defp format_error_reason(:eperm), do: "Operation not permitted"
  defp format_error_reason(:no_valid_response), do: "Device did not respond (not a TSW IO device?)"
  defp format_error_reason(:timeout), do: "Connection timed out"

  defp format_error_reason(reason) when is_atom(reason) do
    reason |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_error_reason(reason), do: inspect(reason)

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

  @doc """
  Transition to :uploading state for firmware upload.

  Generates a unique token that must be provided to release the port.
  Any existing UART process should be closed before calling this.
  Works for any device status - avrdude handles the actual connection.
  """
  @spec mark_uploading(t()) :: {t(), String.t()}
  def mark_uploading(%__MODULE__{} = conn) do
    token = generate_upload_token()
    updated = %__MODULE__{conn | status: :uploading, pid: nil, upload_token: token}
    {updated, token}
  end

  @doc """
  Release upload access and transition back to :failed state.

  The port will be rediscovered on the next scan cycle.
  Returns :ok if the token matches, :error otherwise.
  """
  @spec release_upload(t(), String.t()) :: {:ok, t()} | {:error, :invalid_token}
  def release_upload(%__MODULE__{status: :uploading, upload_token: token} = conn, provided_token) do
    if token == provided_token do
      updated = %__MODULE__{
        conn
        | status: :failed,
          upload_token: nil,
          failed_at: System.monotonic_time(:millisecond)
      }

      {:ok, updated}
    else
      {:error, :invalid_token}
    end
  end

  def release_upload(%__MODULE__{}, _token), do: {:error, :invalid_token}

  defp generate_upload_token do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
