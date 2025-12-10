defmodule TswIo.Firmware.Avrdude do
  @moduledoc """
  Avrdude executable path resolution.

  Finds the avrdude executable, checking bundled locations first,
  then falling back to system PATH.
  """

  @doc """
  Returns the path to the avrdude executable.

  Checks in order:
  1. Tauri sidecar location (next to main executable)
  2. Bundled binary in priv/bin (for releases)
  3. System PATH

  Returns `{:ok, path}` or `{:error, :avrdude_not_found}`.
  """
  @spec executable_path() :: {:ok, String.t()} | {:error, :avrdude_not_found}
  def executable_path do
    cond do
      tauri_path = tauri_sidecar_executable() ->
        {:ok, tauri_path}

      bundled_path = bundled_executable() ->
        {:ok, bundled_path}

      system_path = System.find_executable("avrdude") ->
        {:ok, system_path}

      true ->
        {:error, :avrdude_not_found}
    end
  end

  @doc """
  Returns the path to the avrdude executable, raising on error.
  """
  @spec executable_path!() :: String.t()
  def executable_path! do
    case executable_path() do
      {:ok, path} -> path
      {:error, :avrdude_not_found} -> raise "avrdude executable not found"
    end
  end

  @doc """
  Check if avrdude is available.
  """
  @spec available?() :: boolean()
  def available? do
    match?({:ok, _}, executable_path())
  end

  @doc """
  Get the version of avrdude.
  """
  @spec version() :: {:ok, String.t()} | {:error, term()}
  def version do
    with {:ok, path} <- executable_path() do
      case System.cmd(path, ["-?"], stderr_to_stdout: true) do
        {output, _} ->
          case Regex.run(~r/avrdude version (\S+)/, output) do
            [_, version] -> {:ok, version}
            nil -> {:ok, "unknown"}
          end
      end
    end
  end

  @doc """
  Returns the path to avrdude.conf if available.

  Returns `{:ok, path}` or `{:error, :not_found}`.
  """
  @spec conf_path() :: {:ok, String.t()} | {:error, :not_found}
  def conf_path do
    paths = [
      # Tauri resources location (next to main executable)
      tauri_resource_path("avrdude.conf"),
      # Bundled in priv/bin
      Application.app_dir(:tsw_io, Path.join(["priv", "bin", "avrdude.conf"])),
      # Dev location
      Path.join([:code.priv_dir(:tsw_io), "bin", "avrdude.conf"])
    ]

    case Enum.find(paths, &(is_binary(&1) and File.exists?(&1))) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  # Check for avrdude in Tauri sidecar location
  # Tauri places external binaries in the same directory as the main executable
  defp tauri_sidecar_executable do
    binary_name = avrdude_binary_name()

    # Get the directory of the current executable (works for Burrito releases)
    case System.get_env("APP_PATH") do
      nil ->
        nil

      app_path ->
        path = Path.join(app_path, binary_name)
        if File.exists?(path), do: path, else: nil
    end
  end

  # Get a resource file path from Tauri bundle
  defp tauri_resource_path(filename) do
    case System.get_env("APP_PATH") do
      nil -> nil
      app_path -> Path.join(app_path, filename)
    end
  end

  # Check for bundled avrdude in priv/bin
  defp bundled_executable do
    binary_name = avrdude_binary_name()

    paths = [
      # Release build location
      Application.app_dir(:tsw_io, Path.join(["priv", "bin", binary_name])),
      # Dev build location
      Path.join([:code.priv_dir(:tsw_io), "bin", binary_name])
    ]

    Enum.find(paths, &File.exists?/1)
  end

  # Platform-specific binary name
  defp avrdude_binary_name do
    case :os.type() do
      {:win32, _} -> "avrdude.exe"
      _ -> "avrdude"
    end
  end
end
