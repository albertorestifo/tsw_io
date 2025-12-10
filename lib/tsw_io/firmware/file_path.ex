defmodule TswIo.Firmware.FilePath do
  @moduledoc """
  Utilities for firmware file path management.

  Provides predictable file paths based on release version and board type,
  eliminating the need to track file paths in the database.
  """

  alias TswIo.Firmware.{BoardConfig, FirmwareFile, FirmwareRelease}

  @doc """
  Get the firmware cache directory.

  Uses `~/.tsw_io/firmware_cache` in production,
  `priv/firmware_cache` in development.
  """
  @spec cache_dir() :: String.t()
  def cache_dir do
    if Application.get_env(:tsw_io, :env) == :prod do
      Path.join([System.user_home!(), ".tsw_io", "firmware_cache"])
    else
      Application.app_dir(:tsw_io, "priv/firmware_cache")
    end
  end

  @doc """
  Ensure the firmware cache directory exists.

  Creates the directory if needed.
  """
  @spec ensure_cache_dir() :: :ok | {:error, {:cache_dir_error, term()}}
  def ensure_cache_dir do
    case File.mkdir_p(cache_dir()) do
      :ok -> :ok
      {:error, reason} -> {:error, {:cache_dir_error, reason}}
    end
  end

  @doc """
  Get the expected file path for a firmware file.

  Generates a predictable path based on version and board type:
  `cache_dir/v1.0.1_sparkfun_pro_micro.hex`

  ## Examples

      iex> file = %FirmwareFile{
      ...>   firmware_release: %FirmwareRelease{version: "1.0.1"},
      ...>   board_type: :sparkfun_pro_micro
      ...> }
      iex> FilePath.firmware_path(file)
      "/path/to/cache/v1.0.1_sparkfun_pro_micro.hex"

      iex> FilePath.firmware_path("1.0.1", :arduino_uno)
      "/path/to/cache/v1.0.1_arduino_uno.hex"
  """
  @spec firmware_path(FirmwareFile.t()) :: String.t()
  def firmware_path(%FirmwareFile{firmware_release: %FirmwareRelease{} = release} = file) do
    firmware_path(release.version, file.board_type)
  end

  @spec firmware_path(String.t(), BoardConfig.board_type()) :: String.t()
  def firmware_path(version, board_type) when is_binary(version) and is_atom(board_type) do
    filename = "v#{version}_#{board_type}.hex"
    Path.join(cache_dir(), filename)
  end

  @doc """
  Check if firmware is downloaded for a given file.

  Returns `true` if the file exists on disk, `false` otherwise.

  ## Examples

      iex> file = %FirmwareFile{
      ...>   firmware_release: %FirmwareRelease{version: "1.0.1"},
      ...>   board_type: :arduino_uno
      ...> }
      iex> FilePath.downloaded?(file)
      false
  """
  @spec downloaded?(FirmwareFile.t()) :: boolean()
  def downloaded?(%FirmwareFile{} = file) do
    file
    |> firmware_path()
    |> File.exists?()
  end

  @spec downloaded?(String.t(), BoardConfig.board_type()) :: boolean()
  def downloaded?(version, board_type) when is_binary(version) and is_atom(board_type) do
    version
    |> firmware_path(board_type)
    |> File.exists?()
  end

  @doc """
  List all downloaded firmware files in the cache.

  Returns a list of `{version, board_type, path}` tuples for all .hex files
  that match the expected naming pattern.
  """
  @spec list_downloaded() :: [{String.t(), BoardConfig.board_type(), String.t()}]
  def list_downloaded do
    case File.ls(cache_dir()) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".hex"))
        |> Enum.map(&parse_filename/1)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(fn {version, board_type} ->
          {version, board_type, firmware_path(version, board_type)}
        end)

      {:error, _} ->
        []
    end
  end

  # Parse a filename like "v1.0.1_arduino_uno.hex" into {version, board_type}
  defp parse_filename(filename) do
    case Regex.run(~r/^v([0-9.]+)_([a-z_]+)\.hex$/, filename) do
      [_, version, board_type_str] ->
        # Validate board type is known
        board_type = String.to_atom(board_type_str)

        if board_type in BoardConfig.board_types() do
          {version, board_type}
        else
          nil
        end

      _ ->
        nil
    end
  end
end
