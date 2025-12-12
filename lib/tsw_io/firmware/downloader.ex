defmodule TswIo.Firmware.Downloader do
  @moduledoc """
  Downloads firmware files from GitHub releases.

  Fetches release metadata from the GitHub API and downloads
  HEX files to the local firmware cache.
  """

  require Logger

  alias TswIo.Firmware
  alias TswIo.Firmware.{BoardConfig, FilePath, FirmwareFile}

  @github_repo "albertorestifo/tsw_board"
  @github_api_url "https://api.github.com/repos/#{@github_repo}/releases"

  @doc """
  Fetch releases from GitHub and store new ones in the database.

  Returns `{:ok, new_releases}` where new_releases is a list of
  newly created release records.
  """
  @spec check_for_updates() :: {:ok, [Firmware.FirmwareRelease.t()]} | {:error, term()}
  def check_for_updates do
    case fetch_github_releases() do
      {:ok, releases} ->
        new_releases =
          releases
          |> Enum.map(&parse_release/1)
          |> Enum.map(&store_release/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, release} -> release end)

        {:ok, new_releases}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Download a firmware file to the local cache.

  Returns `{:ok, firmware_file}` on success. The file is saved with a
  predictable name based on version and board type.
  """
  @spec download_firmware(integer()) :: {:ok, FirmwareFile.t()} | {:error, term()}
  def download_firmware(firmware_file_id) do
    with {:ok, file} <- Firmware.get_firmware_file(firmware_file_id, preload: [:firmware_release]),
         :ok <- FilePath.ensure_cache_dir(),
         destination <- FilePath.firmware_path(file),
         {:ok, _} <- download_file(file.download_url, destination) do
      {:ok, file}
    end
  end

  # GitHub API

  defp fetch_github_releases do
    Logger.info("Fetching firmware releases from GitHub")

    case Req.get(@github_api_url, headers: github_headers()) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("GitHub API error: #{status} - #{inspect(body)}")
        {:error, {:github_api_error, status}}

      {:error, reason} ->
        Logger.error("Failed to fetch GitHub releases: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp github_headers do
    headers = [
      {"accept", "application/vnd.github.v3+json"},
      {"user-agent", "tsw_io/1.0"}
    ]

    # Add auth token if configured (for higher rate limits)
    case Application.get_env(:tsw_io, :github_token) do
      nil -> headers
      token -> [{"authorization", "token #{token}"} | headers]
    end
  end

  # Release parsing

  defp parse_release(release) do
    %{
      version: parse_version(release["tag_name"]),
      tag_name: release["tag_name"],
      release_url: release["html_url"],
      release_notes: release["body"],
      published_at: parse_datetime(release["published_at"]),
      assets: parse_assets(release["assets"] || [])
    }
  end

  defp parse_version("v" <> version), do: version
  defp parse_version(version), do: version

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_assets(assets) do
    assets
    |> Enum.filter(&hex_file?/1)
    |> Enum.map(&parse_asset/1)
    |> Enum.filter(&(&1.board_type != nil))
  end

  defp hex_file?(asset) do
    String.ends_with?(asset["name"] || "", ".hex")
  end

  defp parse_asset(asset) do
    filename = asset["name"]

    %{
      filename: filename,
      download_url: asset["browser_download_url"],
      file_size: asset["size"],
      board_type: detect_board_type(filename)
    }
  end

  defp detect_board_type(filename) do
    case BoardConfig.detect_board_type(filename) do
      {:ok, board_type} -> board_type
      :error -> nil
    end
  end

  # Database storage

  defp store_release(release_data) do
    case Firmware.upsert_release(Map.drop(release_data, [:assets])) do
      {:ok, release} ->
        # Store firmware files for this release
        Enum.each(release_data.assets, fn asset ->
          store_firmware_file(release.id, asset)
        end)

        {:ok, release}

      error ->
        error
    end
  end

  defp store_firmware_file(release_id, asset) do
    attrs = %{
      board_type: asset.board_type,
      download_url: asset.download_url,
      file_size: asset.file_size
    }

    case Firmware.get_firmware_file_for_board(release_id, asset.board_type) do
      {:ok, existing} ->
        Firmware.update_firmware_file(existing, attrs)

      {:error, :not_found} ->
        Firmware.create_firmware_file(release_id, attrs)
    end
  end

  # File download

  defp download_file(url, destination) do
    Logger.info("Downloading firmware from #{url}")

    case Req.get(url, into: File.stream!(destination), decode_body: false) do
      {:ok, %{status: 200}} ->
        Logger.info("Downloaded firmware to #{destination}")
        {:ok, destination}

      {:ok, %{status: status}} ->
        File.rm(destination)
        {:error, {:download_failed, status}}

      {:error, reason} ->
        File.rm(destination)
        {:error, reason}
    end
  end
end
