defmodule TswIo.Firmware.UploadManager do
  @moduledoc """
  Coordinates firmware upload operations.

  Tracks in-flight uploads, manages avrdude tasks,
  broadcasts progress events, and handles timeouts.

  Only one upload can be in progress at a time.
  """

  use GenServer

  require Logger

  alias TswIo.Firmware
  alias TswIo.Firmware.{BoardConfig, FilePath, FirmwareFile, Uploader}
  alias TswIo.Serial.Connection

  @pubsub_topic "firmware:uploads"
  @upload_timeout_ms 120_000

  defmodule State do
    @moduledoc false

    @type upload_info :: %{
            upload_id: String.t(),
            port: String.t(),
            board_type: BoardConfig.board_type(),
            firmware_file_id: integer(),
            task_ref: reference() | nil,
            release_token: String.t(),
            started_at: integer()
          }

    @type t :: %__MODULE__{
            current_upload: upload_info() | nil
          }

    defstruct [:current_upload]
  end

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @doc """
  Start a firmware upload.

  ## Returns

    * `{:ok, upload_id}` - Upload started
    * `{:error, :upload_in_progress}` - Another upload is in progress
    * `{:error, :firmware_not_downloaded}` - Firmware file not cached locally
    * `{:error, reason}` - Other error
  """
  @spec start_upload(String.t(), BoardConfig.board_type(), integer()) ::
          {:ok, String.t()} | {:error, term()}
  def start_upload(port, board_type, firmware_file_id) do
    GenServer.call(__MODULE__, {:start_upload, port, board_type, firmware_file_id})
  end

  @doc """
  Cancel the current upload.
  """
  @spec cancel_upload(String.t()) :: :ok | {:error, :not_found}
  def cancel_upload(upload_id) do
    GenServer.call(__MODULE__, {:cancel_upload, upload_id})
  end

  @doc """
  Get the current upload status.
  """
  @spec current_upload() :: State.upload_info() | nil
  def current_upload do
    GenServer.call(__MODULE__, :current_upload)
  end

  @doc """
  Subscribe to upload events.

  Events:
    * `{:upload_started, upload_id, port, board_type}`
    * `{:upload_progress, upload_id, percent, message}`
    * `{:upload_completed, upload_id, duration_ms}`
    * `{:upload_failed, upload_id, reason, message}`
  """
  @spec subscribe_uploads() :: :ok | {:error, term()}
  def subscribe_uploads do
    Phoenix.PubSub.subscribe(TswIo.PubSub, @pubsub_topic)
  end

  # Server callbacks

  @impl true
  def init(%State{} = state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:start_upload, port, board_type, firmware_file_id}, _from, %State{} = state) do
    if state.current_upload != nil do
      {:reply, {:error, :upload_in_progress}, state}
    else
      case do_start_upload(port, board_type, firmware_file_id) do
        {:ok, upload_info} ->
          {:reply, {:ok, upload_info.upload_id}, %{state | current_upload: upload_info}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:cancel_upload, upload_id}, _from, %State{} = state) do
    case state.current_upload do
      %{upload_id: ^upload_id} = upload ->
        do_cancel_upload(upload)
        {:reply, :ok, %{state | current_upload: nil}}

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:current_upload, _from, state) do
    {:reply, state.current_upload, state}
  end

  @impl true
  def handle_info({ref, result}, %State{} = state) when is_reference(ref) do
    # Task completed
    case state.current_upload do
      %{task_ref: ^ref} = upload ->
        Process.demonitor(ref, [:flush])
        handle_upload_result(upload, result)
        {:noreply, %{state | current_upload: nil}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{} = state) do
    # Task crashed
    case state.current_upload do
      %{task_ref: ^ref} = upload ->
        Logger.error("Upload task crashed: #{inspect(reason)}")
        handle_upload_crash(upload, reason)
        {:noreply, %{state | current_upload: nil}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:upload_timeout, upload_id}, %State{} = state) do
    case state.current_upload do
      %{upload_id: ^upload_id} = upload ->
        Logger.warning("Upload timed out: #{upload_id}")
        do_cancel_upload(upload)
        broadcast({:upload_failed, upload_id, :timeout, Uploader.error_message(:timeout)})
        {:noreply, %{state | current_upload: nil}}

      _ ->
        {:noreply, state}
    end
  end

  # Private functions

  defp do_start_upload(port, board_type, firmware_file_id) do
    with {:ok, file} <- Firmware.get_firmware_file(firmware_file_id, preload: [:firmware_release]),
         :ok <- verify_firmware_downloaded(file),
         {:ok, release_token} <- Connection.request_upload_access(port) do
      upload_id = generate_upload_id()

      # Create history entry
      {:ok, _history} =
        Firmware.create_upload_history(%{
          upload_id: upload_id,
          port: port,
          board_type: board_type,
          firmware_file_id: firmware_file_id
        })

      # Start the upload task
      task =
        Task.async(fn ->
          progress_callback = fn percent, message ->
            broadcast({:upload_progress, upload_id, percent, message})
          end

          file_path = FilePath.firmware_path(file)
          Uploader.upload(port, board_type, file_path, progress_callback)
        end)

      # Schedule timeout
      Process.send_after(self(), {:upload_timeout, upload_id}, @upload_timeout_ms)

      upload_info = %{
        upload_id: upload_id,
        port: port,
        board_type: board_type,
        firmware_file_id: firmware_file_id,
        task_ref: task.ref,
        release_token: release_token,
        started_at: System.monotonic_time(:millisecond)
      }

      broadcast({:upload_started, upload_id, port, board_type})
      Logger.info("Started firmware upload #{upload_id} to #{port}")

      {:ok, upload_info}
    end
  end

  defp verify_firmware_downloaded(%FirmwareFile{} = file) do
    if FilePath.downloaded?(file), do: :ok, else: {:error, :firmware_not_downloaded}
  end

  defp do_cancel_upload(upload) do
    # Kill the task if running - demonitor and flush any pending messages
    if upload.task_ref do
      Process.demonitor(upload.task_ref, [:flush])
    end

    # Release the port
    Connection.release_upload_access(upload.port, upload.release_token)

    # Update history
    case Firmware.get_upload_history(upload.upload_id) do
      {:ok, history} -> Firmware.cancel_upload_history(history)
      _ -> :ok
    end

    broadcast({:upload_failed, upload.upload_id, :cancelled, "Upload cancelled by user"})
    Logger.info("Cancelled firmware upload #{upload.upload_id}")
  end

  defp handle_upload_result(upload, {:ok, %{duration_ms: duration_ms, output: output}}) do
    # Release the port
    Connection.release_upload_access(upload.port, upload.release_token)

    # Update history
    case Firmware.get_upload_history(upload.upload_id) do
      {:ok, history} -> Firmware.complete_upload(history, %{avrdude_output: output})
      _ -> :ok
    end

    broadcast({:upload_completed, upload.upload_id, duration_ms})
    Logger.info("Completed firmware upload #{upload.upload_id} in #{duration_ms}ms")
  end

  defp handle_upload_result(upload, {:error, reason, output}) do
    # Release the port
    Connection.release_upload_access(upload.port, upload.release_token)

    # Update history
    error_message = Uploader.error_message(reason)

    case Firmware.get_upload_history(upload.upload_id) do
      {:ok, history} -> Firmware.fail_upload(history, to_string(reason), output)
      _ -> :ok
    end

    broadcast({:upload_failed, upload.upload_id, reason, error_message})
    Logger.error("Failed firmware upload #{upload.upload_id}: #{reason}")
  end

  defp handle_upload_crash(upload, reason) do
    # Release the port
    Connection.release_upload_access(upload.port, upload.release_token)

    # Update history
    case Firmware.get_upload_history(upload.upload_id) do
      {:ok, history} -> Firmware.fail_upload(history, "Task crashed: #{inspect(reason)}", nil)
      _ -> :ok
    end

    broadcast({:upload_failed, upload.upload_id, :crash, "Upload task crashed unexpectedly"})
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(TswIo.PubSub, @pubsub_topic, event)
  end

  defp generate_upload_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
