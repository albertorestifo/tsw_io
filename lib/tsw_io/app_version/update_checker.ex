defmodule TswIo.AppVersion.UpdateChecker do
  @moduledoc """
  Periodically checks for app version updates and notifies users.

  Runs an initial check on startup (after a brief delay) and then
  checks periodically. Broadcasts PubSub events when updates are found.

  This is a simplified in-memory checker without database persistence.
  """

  use GenServer

  require Logger

  alias TswIo.AppVersion

  # PubSub topic for broadcasting update notifications
  @pubsub_topic "app_version:update_notifications"

  # Default check interval: 24 hours
  @default_check_interval_ms :timer.hours(24)

  # Startup delay: wait 5 seconds after app starts before first check
  @startup_delay_ms :timer.seconds(5)

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            check_interval_ms: integer(),
            update_available: boolean(),
            latest_version: String.t() | nil,
            checking: boolean()
          }

    defstruct [
      :check_interval_ms,
      :latest_version,
      update_available: false,
      checking: false
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger an update check.
  """
  @spec check_now() :: :ok
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  @doc """
  Get the current update status.

  Returns:
    * `{:update_available, version}` - New version available
    * `:no_update` - No updates or not checked yet
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
    * `{:app_version_update_available, version}` - New app version found
    * `:app_version_update_dismissed` - User dismissed the notification
    * `{:app_version_update_checking, boolean}` - Check in progress
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(TswIo.PubSub, @pubsub_topic)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    check_interval_ms =
      Application.get_env(:tsw_io, :app_version_check_interval_ms, @default_check_interval_ms)

    state = %State{
      check_interval_ms: check_interval_ms,
      update_available: false,
      latest_version: nil,
      checking: false
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
      if state.update_available && state.latest_version do
        {:update_available, state.latest_version}
      else
        :no_update
      end

    {:reply, response, state}
  end

  @impl true
  def handle_cast(:check_now, %State{} = state) do
    {:noreply, maybe_perform_check(state)}
  end

  @impl true
  def handle_cast(:dismiss_notification, %State{} = state) do
    broadcast(:app_version_update_dismissed)

    new_state = %{state | update_available: false, latest_version: nil}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:startup_check, %State{} = state) do
    Logger.info("Performing startup app version update check")
    {:noreply, maybe_perform_check(state)}
  end

  @impl true
  def handle_info(:periodic_check, %State{} = state) do
    Logger.debug("Periodic app version update check")
    new_state = maybe_perform_check(state)

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

  # Private Functions

  defp maybe_perform_check(%State{checking: true} = state) do
    Logger.debug("Skipping app version check - already in progress")
    state
  end

  defp maybe_perform_check(%State{} = state) do
    perform_check_async(state)
  end

  defp perform_check_async(%State{} = state) do
    broadcast({:app_version_update_checking, true})

    # Run the check in a Task to avoid blocking
    Task.async(fn ->
      case AppVersion.check_for_updates() do
        {:ok, latest_version} when is_binary(latest_version) ->
          {:ok, true, latest_version}

        {:ok, :up_to_date} ->
          {:ok, false, nil}

        {:error, reason} ->
          {:error, reason}
      end
    end)

    %{state | checking: true}
  end

  defp handle_check_result({:ok, update_available, version}, %State{} = state) do
    broadcast({:app_version_update_checking, false})

    new_state = %{
      state
      | update_available: update_available,
        latest_version: version,
        checking: false
    }

    if update_available do
      Logger.info("App version update available: #{version}")
      broadcast({:app_version_update_available, version})
    else
      Logger.debug("No new app version updates found")
    end

    {:noreply, new_state}
  end

  defp handle_check_result({:error, reason}, %State{} = state) do
    Logger.warning("App version update check failed: #{inspect(reason)}")
    broadcast({:app_version_update_checking, false})

    {:noreply, %{state | checking: false}}
  end

  defp schedule_next_check(interval_ms) do
    Process.send_after(self(), :periodic_check, interval_ms)
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(TswIo.PubSub, @pubsub_topic, event)
  end
end
