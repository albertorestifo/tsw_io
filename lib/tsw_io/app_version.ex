defmodule TswIo.AppVersion do
  @moduledoc """
  Context for app version management and update checking.

  Handles checking for new app releases on GitHub and
  comparing against the current version.
  """

  @github_repo "albertorestifo/tsw_io"

  @doc """
  Get the current app version from the application spec.
  """
  @spec current_version() :: String.t()
  def current_version do
    :tsw_io
    |> Application.spec(:vsn)
    |> to_string()
  end

  @doc """
  Get the current update status.

  Returns `:no_update` if UpdateChecker is not running (e.g., in tests).
  """
  @spec check_update_status() :: {:update_available, String.t()} | :no_update
  def check_update_status do
    TswIo.AppVersion.UpdateChecker.get_update_status()
  catch
    :exit, {:noproc, _} -> :no_update
  end

  @doc """
  Dismiss the update notification.

  Returns `:ok` even if UpdateChecker is not running.
  """
  @spec dismiss_update_notification() :: :ok
  def dismiss_update_notification do
    TswIo.AppVersion.UpdateChecker.dismiss_notification()
  catch
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Subscribe to update notification events.
  """
  @spec subscribe_update_notifications() :: :ok | {:error, term()}
  def subscribe_update_notifications do
    TswIo.AppVersion.UpdateChecker.subscribe()
  end

  @doc """
  Trigger a manual update check.

  Returns `:ok` even if UpdateChecker is not running.
  """
  @spec trigger_update_check() :: :ok
  def trigger_update_check do
    TswIo.AppVersion.UpdateChecker.check_now()
  catch
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Check for new app releases on GitHub.

  Compares the latest GitHub release with the current app version.
  Returns `{:ok, latest_version}` if update available, `{:ok, :up_to_date}` otherwise.
  """
  @spec check_for_updates() :: {:ok, String.t()} | {:ok, :up_to_date} | {:error, term()}
  def check_for_updates do
    with {:ok, latest_version} <- fetch_latest_version(),
         :gt <- compare_versions(latest_version, current_version()) do
      {:ok, latest_version}
    else
      :lt -> {:ok, :up_to_date}
      :eq -> {:ok, :up_to_date}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch the latest release version from GitHub.
  """
  @spec fetch_latest_version() :: {:ok, String.t()} | {:error, term()}
  def fetch_latest_version do
    url = "https://api.github.com/repos/#{@github_repo}/releases/latest"

    case Req.get(url, headers: github_headers()) do
      {:ok, %{status: 200, body: body}} ->
        version = parse_version(body["tag_name"])
        {:ok, version}

      {:ok, %{status: 404}} ->
        {:error, :no_releases}

      {:ok, %{status: status}} ->
        {:error, {:github_api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the GitHub releases page URL.
  """
  @spec releases_url() :: String.t()
  def releases_url do
    "https://github.com/#{@github_repo}/releases"
  end

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

  # Private functions

  defp github_headers do
    [
      {"accept", "application/vnd.github.v3+json"},
      {"user-agent", "tsw_io/#{current_version()}"}
    ]
  end

  defp parse_version("v" <> version), do: version
  defp parse_version(version), do: version

  defp normalize_version("v" <> version), do: version
  defp normalize_version(version), do: version
end
