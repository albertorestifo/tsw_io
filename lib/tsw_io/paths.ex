defmodule TswIo.Paths do
  @moduledoc """
  Platform-specific path resolution for application data.

  Returns appropriate directories based on the operating system:
  - macOS: ~/Library/Application Support/TswIo
  - Windows: %APPDATA%/TswIo
  - Linux: ~/.local/share/tsw_io (or $XDG_DATA_HOME/tsw_io)
  """

  @app_name "TswIo"
  @app_name_lower "tsw_io"

  @doc """
  Returns the platform-specific data directory for the application.

  The directory is created if it doesn't exist.
  """
  @spec data_dir() :: String.t()
  def data_dir do
    dir = get_data_dir()
    ensure_dir_exists(dir)
    dir
  end

  @doc """
  Returns the path to the database file.

  The parent directory is created if it doesn't exist.
  """
  @spec database_path() :: String.t()
  def database_path do
    Path.join(data_dir(), "#{@app_name_lower}.db")
  end

  defp get_data_dir do
    case :os.type() do
      {:unix, :darwin} ->
        # macOS: ~/Library/Application Support/TswIo
        home = System.get_env("HOME") || "~"
        Path.join([home, "Library", "Application Support", @app_name])

      {:win32, _} ->
        # Windows: %APPDATA%/TswIo
        appdata = System.get_env("APPDATA") || System.get_env("LOCALAPPDATA") || "."
        Path.join(appdata, @app_name)

      {:unix, _} ->
        # Linux/BSD: $XDG_DATA_HOME/tsw_io or ~/.local/share/tsw_io
        xdg_data = System.get_env("XDG_DATA_HOME")

        base_dir =
          if xdg_data && xdg_data != "" do
            xdg_data
          else
            home = System.get_env("HOME") || "~"
            Path.join([home, ".local", "share"])
          end

        Path.join(base_dir, @app_name_lower)
    end
  end

  defp ensure_dir_exists(dir) do
    File.mkdir_p!(dir)
  end
end
