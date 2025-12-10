defmodule TswIo.Firmware do
  @moduledoc """
  Context for firmware management and device uploads.

  Handles downloading firmware from GitHub releases and
  flashing devices via avrdude.
  """

  import Ecto.Query

  alias TswIo.Repo
  alias TswIo.Firmware.{BoardConfig, FirmwareFile, FirmwareRelease, UploadHistory}

  # Delegate upload operations to UploadManager
  defdelegate start_upload(port, board_type, firmware_file_id), to: TswIo.Firmware.UploadManager
  defdelegate cancel_upload(upload_id), to: TswIo.Firmware.UploadManager
  defdelegate subscribe_uploads(), to: TswIo.Firmware.UploadManager
  defdelegate current_upload(), to: TswIo.Firmware.UploadManager

  # Delegate download operations to Downloader
  defdelegate check_for_updates(), to: TswIo.Firmware.Downloader
  defdelegate download_firmware(firmware_file_id), to: TswIo.Firmware.Downloader

  # Update check operations

  @doc """
  Get the current update status.

  Returns `:no_update` if UpdateChecker is not running (e.g., in tests).
  """
  @spec check_update_status() :: {:update_available, String.t()} | :no_update
  def check_update_status do
    TswIo.Firmware.UpdateChecker.get_update_status()
  catch
    :exit, {:noproc, _} -> :no_update
  end

  @doc """
  Dismiss the update notification.

  Returns `:ok` even if UpdateChecker is not running.
  """
  @spec dismiss_update_notification() :: :ok
  def dismiss_update_notification do
    TswIo.Firmware.UpdateChecker.dismiss_notification()
  catch
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Subscribe to update notification events.

  Returns `{:error, :not_running}` if UpdateChecker is not running.
  """
  @spec subscribe_update_notifications() :: :ok | {:error, term()}
  def subscribe_update_notifications do
    TswIo.Firmware.UpdateChecker.subscribe()
  end

  @doc """
  Trigger a manual update check.

  Returns `:ok` even if UpdateChecker is not running.
  """
  @spec trigger_update_check() :: :ok
  def trigger_update_check do
    TswIo.Firmware.UpdateChecker.check_now()
  catch
    :exit, {:noproc, _} -> :ok
  end

  # Re-export BoardConfig functions for convenience
  defdelegate board_types(), to: BoardConfig
  defdelegate get_board_config(board_type), to: BoardConfig, as: :get_config
  defdelegate board_select_options(), to: BoardConfig, as: :select_options

  # Release operations

  @doc """
  List all cached firmware releases, ordered by version (newest first).
  """
  @spec list_releases(keyword()) :: [FirmwareRelease.t()]
  def list_releases(opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    FirmwareRelease
    |> order_by([r], desc: r.published_at)
    |> Repo.all()
    |> Repo.preload(preloads)
  end

  @doc """
  Get the latest firmware release.
  """
  @spec get_latest_release(keyword()) :: {:ok, FirmwareRelease.t()} | {:error, :not_found}
  def get_latest_release(opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case FirmwareRelease
         |> order_by([r], desc: r.published_at)
         |> limit(1)
         |> Repo.one() do
      nil -> {:error, :not_found}
      release -> {:ok, Repo.preload(release, preloads)}
    end
  end

  @doc """
  Get a firmware release by ID.
  """
  @spec get_release(integer(), keyword()) :: {:ok, FirmwareRelease.t()} | {:error, :not_found}
  def get_release(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Repo.get(FirmwareRelease, id) do
      nil -> {:error, :not_found}
      release -> {:ok, Repo.preload(release, preloads)}
    end
  end

  @doc """
  Get a firmware release by tag name (e.g., "v1.0.0").
  """
  @spec get_release_by_tag(String.t(), keyword()) ::
          {:ok, FirmwareRelease.t()} | {:error, :not_found}
  def get_release_by_tag(tag_name, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Repo.get_by(FirmwareRelease, tag_name: tag_name) do
      nil -> {:error, :not_found}
      release -> {:ok, Repo.preload(release, preloads)}
    end
  end

  @doc """
  Create a firmware release from parsed GitHub data.
  """
  @spec create_release(map()) :: {:ok, FirmwareRelease.t()} | {:error, Ecto.Changeset.t()}
  def create_release(attrs) do
    %FirmwareRelease{}
    |> FirmwareRelease.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create or update a firmware release by tag name.
  """
  @spec upsert_release(map()) :: {:ok, FirmwareRelease.t()} | {:error, Ecto.Changeset.t()}
  def upsert_release(%{tag_name: tag_name} = attrs) do
    case get_release_by_tag(tag_name) do
      {:ok, existing} ->
        existing
        |> FirmwareRelease.changeset(attrs)
        |> Repo.update()

      {:error, :not_found} ->
        create_release(attrs)
    end
  end

  # Firmware file operations

  @doc """
  Get a firmware file by ID.
  """
  @spec get_firmware_file(integer(), keyword()) ::
          {:ok, FirmwareFile.t()} | {:error, :not_found}
  def get_firmware_file(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Repo.get(FirmwareFile, id) do
      nil -> {:error, :not_found}
      file -> {:ok, Repo.preload(file, preloads)}
    end
  end

  @doc """
  Get a firmware file for a specific release and board type.
  """
  @spec get_firmware_file_for_board(integer(), BoardConfig.board_type()) ::
          {:ok, FirmwareFile.t()} | {:error, :not_found}
  def get_firmware_file_for_board(release_id, board_type) do
    case Repo.get_by(FirmwareFile, firmware_release_id: release_id, board_type: board_type) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  @doc """
  Create a firmware file for a release.
  """
  @spec create_firmware_file(integer(), map()) ::
          {:ok, FirmwareFile.t()} | {:error, Ecto.Changeset.t()}
  def create_firmware_file(release_id, attrs) do
    %FirmwareFile{firmware_release_id: release_id}
    |> FirmwareFile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a firmware file (e.g., after downloading).
  """
  @spec update_firmware_file(FirmwareFile.t(), map()) ::
          {:ok, FirmwareFile.t()} | {:error, Ecto.Changeset.t()}
  def update_firmware_file(%FirmwareFile{} = file, attrs) do
    file
    |> FirmwareFile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Check if a firmware file has been downloaded locally.
  """
  @spec firmware_downloaded?(FirmwareFile.t()) :: boolean()
  defdelegate firmware_downloaded?(file), to: FirmwareFile, as: :downloaded?

  # Upload history operations

  @doc """
  List upload history, ordered by most recent first.

  ## Options

    * `:limit` - Maximum number of records to return (default: 50)
    * `:preload` - List of associations to preload (default: [])
  """
  @spec list_upload_history(keyword()) :: [UploadHistory.t()]
  def list_upload_history(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    preloads = Keyword.get(opts, :preload, [])

    UploadHistory
    |> order_by([h], desc: h.started_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(preloads)
  end

  @doc """
  Create an upload history entry.
  """
  @spec create_upload_history(map()) :: {:ok, UploadHistory.t()} | {:error, Ecto.Changeset.t()}
  def create_upload_history(attrs) do
    attrs
    |> UploadHistory.start_changeset()
    |> Repo.insert()
  end

  @doc """
  Get an upload history entry by upload_id.
  """
  @spec get_upload_history(String.t()) :: {:ok, UploadHistory.t()} | {:error, :not_found}
  def get_upload_history(upload_id) do
    case Repo.get_by(UploadHistory, upload_id: upload_id) do
      nil -> {:error, :not_found}
      history -> {:ok, history}
    end
  end

  @doc """
  Mark an upload as completed.
  """
  @spec complete_upload(UploadHistory.t(), map()) ::
          {:ok, UploadHistory.t()} | {:error, Ecto.Changeset.t()}
  def complete_upload(%UploadHistory{} = history, attrs \\ %{}) do
    history
    |> UploadHistory.complete_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Mark an upload as failed.
  """
  @spec fail_upload(UploadHistory.t(), String.t(), String.t() | nil) ::
          {:ok, UploadHistory.t()} | {:error, Ecto.Changeset.t()}
  def fail_upload(%UploadHistory{} = history, error_message, avrdude_output \\ nil) do
    history
    |> UploadHistory.fail_changeset(error_message, avrdude_output)
    |> Repo.update()
  end

  @doc """
  Mark an upload as cancelled.
  """
  @spec cancel_upload_history(UploadHistory.t()) ::
          {:ok, UploadHistory.t()} | {:error, Ecto.Changeset.t()}
  def cancel_upload_history(%UploadHistory{} = history) do
    history
    |> UploadHistory.cancel_changeset()
    |> Repo.update()
  end

  # Version comparison

  @doc """
  Compare two version strings.

  Returns:
  - `:gt` if v1 > v2
  - `:lt` if v1 < v2
  - `:eq` if v1 == v2
  """
  @spec compare_versions(String.t(), String.t()) :: :gt | :lt | :eq
  def compare_versions(v1, v2) do
    case Version.compare(normalize_version(v1), normalize_version(v2)) do
      :gt -> :gt
      :lt -> :lt
      :eq -> :eq
    end
  end

  @doc """
  Check if there's a newer version available than the given version.
  """
  @spec update_available?(String.t()) :: boolean()
  def update_available?(current_version) do
    case get_latest_release() do
      {:ok, release} ->
        compare_versions(release.version, current_version) == :gt

      {:error, :not_found} ->
        false
    end
  end

  # Normalize version string (remove 'v' prefix if present)
  defp normalize_version("v" <> version), do: version
  defp normalize_version(version), do: version
end
