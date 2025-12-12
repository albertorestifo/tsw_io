defmodule TswIo.Firmware.UpdateChecker do
  @moduledoc """
  Periodically checks for firmware updates and notifies users.

  Runs an initial check on startup (after a brief delay) and then
  checks periodically. Broadcasts PubSub events only when:
  1. A new firmware version is available on GitHub
  2. At least one connected device has firmware older than the latest

  Rate limiting:
  - Checks no more than once per hour
  - Stores last check timestamp in database to persist across restarts
  - Configurable check interval (default: 24 hours)
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias TswIo.Firmware
  alias TswIo.Firmware.UpdateCheck
  alias TswIo.Repo
  alias TswIo.Serial.Connection

  # PubSub topic for broadcasting update notifications
  @pubsub_topic "firmware:update_notifications"

  # PubSub topic for device updates
  @device_updates_topic "device_updates"

  # Default check interval: 24 hours
  @default_check_interval_ms :timer.hours(24)

  # Rate limit: don't check more than once per hour
  @min_check_interval_ms :timer.hours(1)

  # Startup delay: wait 5 seconds after app starts before first check
  @startup_delay_ms :timer.seconds(5)

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            last_check_at: DateTime.t() | nil,
            check_interval_ms: integer(),
            latest_version: String.t() | nil,
            checking: boolean(),
            notification_shown: boolean()
          }

    defstruct [
      :last_check_at,
      :check_interval_ms,
      :latest_version,
      checking: false,
      notification_shown: false
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger an update check.

  Respects rate limiting - will skip if checked recently.
  """
  @spec check_now() :: :ok
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  @doc """
  Get the current update status.

  Only returns `{:update_available, version}` if a connected device
  actually needs the update (has older firmware).

  Returns:
    * `{:update_available, version}` - New version available and device needs it
    * `:no_update` - No updates, not checked yet, or no device needs update
  """
  @spec get_update_status() :: {:update_available, String.t()} | :no_update
  def get_update_status do
    GenServer.call(__MODULE__, :get_update_status)
  end

  @doc """
  Dismiss the update notification.

  This doesn't prevent future checks, just clears the current notification.
  """
  @spec dismiss_notification() :: :ok
  def dismiss_notification do
    GenServer.cast(__MODULE__, :dismiss_notification)
  end

  @doc """
  Subscribe to update notification events.

  Events:
    * `{:firmware_update_available, version}` - New firmware version found
    * `:firmware_update_dismissed` - User dismissed the notification
    * `{:firmware_update_checking, boolean}` - Check in progress
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(TswIo.PubSub, @pubsub_topic)
  end

  # Test Helpers

  @doc false
  def reset_state_for_test do
    GenServer.call(__MODULE__, :reset_state_for_test)
  end

  @doc false
  def disable_automatic_checks_for_test do
    GenServer.call(__MODULE__, :disable_automatic_checks)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    check_interval_ms =
      Application.get_env(:tsw_io, :firmware_check_interval_ms, @default_check_interval_ms)

    # Subscribe to device updates to know when devices connect/disconnect
    Phoenix.PubSub.subscribe(TswIo.PubSub, @device_updates_topic)

    # Load last check from database
    last_check = get_last_check_from_db()

    state = %State{
      last_check_at: last_check && last_check.checked_at,
      check_interval_ms: check_interval_ms,
      latest_version: nil,
      checking: false,
      notification_shown: false
    }

    # Schedule startup check
    Process.send_after(self(), :startup_check, @startup_delay_ms)

    # Schedule periodic checks
    schedule_next_check(check_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_update_status, _from, %State{} = state) do
    response =
      if state.latest_version && device_needs_update?(state.latest_version) do
        {:update_available, state.latest_version}
      else
        :no_update
      end

    {:reply, response, state}
  end

  @impl true
  def handle_call(:reset_state_for_test, _from, %State{} = state) do
    new_state = %{
      state
      | latest_version: nil,
        checking: false,
        notification_shown: false
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:disable_automatic_checks, _from, %State{} = state) do
    # Set last_check_at to a far future time to prevent automatic checks
    far_future = DateTime.utc_now() |> DateTime.add(365, :day)

    new_state = %{state | last_check_at: far_future}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:check_now, %State{} = state) do
    {:noreply, maybe_perform_check(state, _force = true)}
  end

  @impl true
  def handle_cast(:dismiss_notification, %State{} = state) do
    broadcast(:firmware_update_dismissed)

    # Keep latest_version so we can re-show if a new device connects
    # but mark notification as dismissed for current session
    new_state = %{state | notification_shown: false}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:startup_check, %State{} = state) do
    Logger.info("Performing startup firmware update check")
    {:noreply, maybe_perform_check(state, _force = false)}
  end

  @impl true
  def handle_info(:periodic_check, %State{} = state) do
    Logger.debug("Periodic firmware update check")
    new_state = maybe_perform_check(state, _force = false)

    # Schedule next periodic check
    schedule_next_check(state.check_interval_ms)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, %State{} = state) when is_reference(ref) do
    # Handle Task result
    Process.demonitor(ref, [:flush])
    handle_check_result(result, state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %State{} = state) do
    # Task process died - just reset checking state
    {:noreply, %{state | checking: false}}
  end

  # Handle device updates - check if we should show/hide the notification
  @impl true
  def handle_info({:devices_updated, _devices}, %State{latest_version: nil} = state) do
    # No version info yet, nothing to do
    {:noreply, state}
  end

  @impl true
  def handle_info({:devices_updated, _devices}, %State{} = state) do
    # Re-evaluate whether to show the notification based on connected devices
    new_state = maybe_broadcast_update(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp maybe_perform_check(%State{checking: true} = state, _force) do
    Logger.debug("Skipping firmware check - already in progress")
    state
  end

  defp maybe_perform_check(%State{} = state, force) do
    if force || should_check?(state.last_check_at) do
      perform_check_async(state)
    else
      Logger.debug("Skipping firmware check - rate limited")
      state
    end
  end

  defp should_check?(nil), do: true

  defp should_check?(last_check_at) do
    now = DateTime.utc_now()
    elapsed_ms = DateTime.diff(now, last_check_at, :millisecond)
    elapsed_ms >= @min_check_interval_ms
  end

  defp perform_check_async(%State{} = state) do
    broadcast({:firmware_update_checking, true})

    # Run the check in a Task to avoid blocking
    Task.async(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case Firmware.check_for_updates() do
        {:ok, new_releases} ->
          handle_check_success(now, new_releases)

        {:error, reason} ->
          handle_check_error(now, reason)
      end
    end)

    %{state | checking: true}
  end

  defp handle_check_success(checked_at, new_releases) do
    # Get latest release to compare versions
    case Firmware.get_latest_release() do
      {:ok, latest_release} ->
        update_available = length(new_releases) > 0

        # Record check in database
        record_check(checked_at, update_available, latest_release.version, nil)

        {:ok, update_available, latest_release.version, checked_at}

      {:error, :not_found} ->
        # No releases in DB
        record_check(checked_at, false, nil, "No releases found")
        {:ok, false, nil, checked_at}
    end
  end

  defp handle_check_error(checked_at, reason) do
    Logger.warning("Firmware update check failed: #{inspect(reason)}")

    error_message =
      case reason do
        {:github_api_error, status} -> "GitHub API error: #{status}"
        _ -> inspect(reason)
      end

    record_check(checked_at, false, nil, error_message)

    {:error, reason, checked_at}
  end

  defp handle_check_result({:ok, _new_releases_exist, version, checked_at}, %State{} = state) do
    broadcast({:firmware_update_checking, false})

    new_state = %{
      state
      | last_check_at: checked_at,
        latest_version: version,
        checking: false
    }

    # Check if any connected device needs this update
    new_state = maybe_broadcast_update(new_state)

    {:noreply, new_state}
  end

  defp handle_check_result({:error, _reason, checked_at}, %State{} = state) do
    broadcast({:firmware_update_checking, false})

    new_state = %{state | last_check_at: checked_at, checking: false}

    {:noreply, new_state}
  end

  defp record_check(checked_at, found_updates, latest_version, error_message) do
    attrs = %{
      checked_at: checked_at,
      found_updates: found_updates,
      latest_version: latest_version,
      error_message: error_message
    }

    %UpdateCheck{}
    |> UpdateCheck.changeset(attrs)
    |> Repo.insert()

    # Cleanup old records (keep last 100)
    cleanup_old_checks()
  end

  defp cleanup_old_checks do
    # Keep last 100 checks for debugging/analytics
    subquery =
      from c in UpdateCheck,
        order_by: [desc: c.checked_at],
        limit: 100,
        select: c.id

    Repo.delete_all(
      from c in UpdateCheck,
        where: c.id not in subquery(subquery)
    )
  end

  defp get_last_check_from_db do
    UpdateCheck
    |> order_by([c], desc: c.checked_at)
    |> limit(1)
    |> Repo.one()
  end

  defp schedule_next_check(interval_ms) do
    Process.send_after(self(), :periodic_check, interval_ms)
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(TswIo.PubSub, @pubsub_topic, event)
  end

  # Check if we should broadcast an update notification and update state
  defp maybe_broadcast_update(%State{latest_version: nil} = state), do: state

  defp maybe_broadcast_update(%State{latest_version: version} = state) do
    needs_update = device_needs_update?(version)

    cond do
      needs_update and not state.notification_shown ->
        # Device needs update and we haven't shown notification yet
        Logger.info("Firmware update available: #{version} (device needs update)")
        broadcast({:firmware_update_available, version})
        %{state | notification_shown: true}

      not needs_update and state.notification_shown ->
        # No device needs update anymore, dismiss notification
        Logger.debug("No connected device needs firmware update, dismissing notification")
        broadcast(:firmware_update_dismissed)
        %{state | notification_shown: false}

      true ->
        # No change needed
        state
    end
  end

  # Check if any connected device has firmware older than the latest version
  defp device_needs_update?(latest_version) do
    Connection.connected_devices()
    |> Enum.filter(&(&1.device_version != nil))
    |> Enum.any?(fn device ->
      version_older_than?(device.device_version, latest_version)
    end)
  end

  # Compare semantic versions (e.g., "1.0.0" < "1.0.1")
  defp version_older_than?(device_version, latest_version) do
    case {parse_version(device_version), parse_version(latest_version)} do
      {{:ok, device}, {:ok, latest}} ->
        device < latest

      _ ->
        # If we can't parse versions, assume update is needed for safety
        true
    end
  end

  defp parse_version(version_string) when is_binary(version_string) do
    # Remove leading 'v' if present
    version_string = String.trim_leading(version_string, "v")

    case String.split(version_string, ".") do
      [major, minor, patch] ->
        with {maj, ""} <- Integer.parse(major),
             {min, ""} <- Integer.parse(minor),
             {pat, ""} <- Integer.parse(patch) do
          {:ok, {maj, min, pat}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_version(_), do: :error
end
