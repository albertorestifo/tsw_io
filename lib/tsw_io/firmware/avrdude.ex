defmodule TswIo.Firmware.Avrdude do
  @moduledoc """
  Avrdude executable path resolution.

  Finds the avrdude executable, checking bundled locations first,
  then falling back to system PATH.
  """

  @doc """
  Returns the path to the avrdude executable.

  Checks in order:
  1. Bundled binary in priv/bin (for releases)
  2. System PATH

  Returns `{:ok, path}` or `{:error, :avrdude_not_found}`.
  """
  @spec executable_path() :: {:ok, String.t()} | {:error, :avrdude_not_found}
  def executable_path do
    cond do
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

  # Check for bundled avrdude in priv/bin
  defp bundled_executable do
    # Try platform-specific binary name
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
