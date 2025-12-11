defmodule TswIoWeb.SimulatorConfigLive do
  @moduledoc """
  LiveView for configuring the TSW API connection.
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents

  alias TswIo.Serial.Connection
  alias TswIo.Simulator
  alias TswIo.Simulator.Config

  @impl true
  def mount(_params, _session, socket) do
    # NavHook handles nav subscriptions and nav state
    # We still need page-specific state
    status = Simulator.get_status()
    config_result = Simulator.get_config()
    is_windows = Simulator.windows?()

    socket =
      socket
      |> assign(:status, status)
      |> assign(:is_windows, is_windows)
      |> assign_config_form(config_result)
      |> assign(:show_manual, !is_windows)
      |> assign(:auto_detecting, false)

    {:ok, socket}
  end

  # PubSub handlers - update both nav state and local status
  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, :nav_devices, devices)}
  end

  @impl true
  def handle_info({:simulator_status_changed, status}, socket) do
    socket =
      socket
      |> assign(:nav_simulator_status, status)
      |> assign(:status, status)

    {:noreply, socket}
  end

  # Nav component events
  @impl true
  def handle_event("nav_toggle_dropdown", _, socket) do
    {:noreply, assign(socket, :nav_dropdown_open, !socket.assigns.nav_dropdown_open)}
  end

  @impl true
  def handle_event("nav_close_dropdown", _, socket) do
    {:noreply, assign(socket, :nav_dropdown_open, false)}
  end

  @impl true
  def handle_event("nav_scan_devices", _, socket) do
    Connection.scan()
    {:noreply, assign(socket, :nav_scanning, true)}
  end

  @impl true
  def handle_event("nav_disconnect_device", %{"port" => port}, socket) do
    Connection.disconnect(port)
    {:noreply, socket}
  end

  # Page-specific events
  @impl true
  def handle_event("validate", %{"config" => config_params}, socket) do
    changeset =
      socket.assigns.config
      |> Config.changeset(config_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"config" => config_params}, socket) do
    case Simulator.save_config(config_params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> put_flash(:info, "Simulator configuration saved successfully")
         |> assign_config_form({:ok, config})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("auto_detect", _params, socket) do
    socket = assign(socket, :auto_detecting, true)

    case Simulator.auto_configure() do
      {:ok, config} ->
        {:noreply,
         socket
         |> put_flash(:info, "Auto-detected simulator configuration")
         |> assign_config_form({:ok, config})
         |> assign(:auto_detecting, false)}

      {:error, :file_not_found} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Could not find API key file. Make sure you've enabled the API in Steam launch options and started the game at least once."
         )
         |> assign(:auto_detecting, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Auto-detection failed: #{inspect(reason)}")
         |> assign(:auto_detecting, false)}
    end
  end

  @impl true
  def handle_event("retry", _params, socket) do
    Simulator.retry_connection()
    {:noreply, put_flash(socket, :info, "Retrying connection...")}
  end

  @impl true
  def handle_event("toggle_manual", _params, socket) do
    {:noreply, assign(socket, :show_manual, !socket.assigns.show_manual)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case socket.assigns.config do
      %Config{id: id} when not is_nil(id) ->
        case Simulator.delete_config(socket.assigns.config) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Configuration deleted")
             |> assign_config_form({:error, :not_found})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete configuration")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp assign_config_form(socket, {:ok, %Config{} = config}) do
    changeset = Config.changeset(config, %{})

    socket
    |> assign(:config, config)
    |> assign(:form, to_form(changeset))
  end

  defp assign_config_form(socket, {:error, :not_found}) do
    config = %Config{url: Simulator.default_url()}
    changeset = Config.changeset(config, %{})

    socket
    |> assign(:config, config)
    |> assign(:form, to_form(changeset))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.nav_header
        devices={@nav_devices}
        simulator_status={@nav_simulator_status}
        firmware_update={@nav_firmware_update}
        app_version_update={@nav_app_version_update}
        firmware_checking={@nav_firmware_checking}
        dropdown_open={@nav_dropdown_open}
        scanning={@nav_scanning}
        current_path={@nav_current_path}
      />

      <.breadcrumb items={[
        %{label: "Home", path: ~p"/"},
        %{label: "Simulator Configuration"}
      ]} />

      <main class="flex-1 p-4 sm:p-8">
        <div class="max-w-2xl mx-auto">
          <header class="mb-8">
            <h1 class="text-2xl font-semibold">Simulator Configuration</h1>
            <p class="text-sm text-base-content/70 mt-1">
              Configure connection to Train Sim World API
            </p>
          </header>

          <.connection_status status={@status} />

          <.form for={@form} phx-change="validate" phx-submit="save" class="mt-8" id="config-form">
            <.windows_config
              :if={@is_windows and not @show_manual}
              auto_detecting={@auto_detecting}
              config={@config}
            />

            <.manual_config :if={@show_manual} form={@form} is_windows={@is_windows} />

            <div class="mt-6 flex flex-wrap gap-4">
              <button type="submit" class="btn btn-primary">
                Save Configuration
              </button>

              <button
                :if={@is_windows and not @show_manual}
                type="button"
                phx-click="toggle_manual"
                class="btn btn-ghost"
              >
                Manual Configuration
              </button>

              <button
                :if={@is_windows and @show_manual}
                type="button"
                phx-click="toggle_manual"
                class="btn btn-ghost"
              >
                Use Auto-Detection
              </button>

              <button
                :if={@config.id}
                type="button"
                phx-click="delete"
                class="btn btn-error btn-outline ml-auto"
                data-confirm="Are you sure you want to delete this configuration?"
              >
                Delete
              </button>
            </div>
          </.form>
        </div>
      </main>
    </div>
    """
  end

  attr :status, :map, required: true

  defp connection_status(assigns) do
    ~H"""
    <div class={["alert", status_alert_class(@status.status)]}>
      <div class="flex items-center gap-3 w-full">
        <span class={["w-3 h-3 rounded-full flex-shrink-0", status_dot_color(@status.status)]} />
        <div class="flex-1 min-w-0">
          <h3 class="font-medium">{status_title(@status.status)}</h3>
          <p class="text-sm opacity-80">{status_message(@status)}</p>
        </div>
        <button
          :if={@status.status == :error}
          phx-click="retry"
          class="btn btn-sm flex-shrink-0"
        >
          Retry
        </button>
      </div>
    </div>
    """
  end

  attr :auto_detecting, :boolean, required: true
  attr :config, :map, required: true

  defp windows_config(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-xl p-6">
      <h3 class="font-medium mb-4">Windows Auto-Detection</h3>

      <div class="prose prose-sm mb-6">
        <p class="text-base-content/70">
          To enable the TSW API, follow these steps:
        </p>
        <ol class="text-base-content/70 space-y-1">
          <li>Open Steam and go to your Library</li>
          <li>Right-click on Train Sim World 6 and select Properties</li>
          <li>
            In the General tab, add <code class="bg-base-300 px-1 rounded">-HTTPAPI</code>
            to Launch Options
          </li>
          <li>Close and restart Train Sim World 6</li>
          <li>Click the button below to auto-detect the API key</li>
        </ol>
      </div>

      <button
        type="button"
        phx-click="auto_detect"
        disabled={@auto_detecting}
        class="btn btn-primary w-full"
      >
        <.icon :if={@auto_detecting} name="hero-arrow-path" class="w-4 h-4 animate-spin" />
        {if @auto_detecting, do: "Detecting...", else: "Auto-Detect Configuration"}
      </button>

      <p :if={@config.auto_detected} class="text-sm text-success mt-4 flex items-center gap-2">
        <.icon name="hero-check-circle" class="w-4 h-4" />
        Configuration was auto-detected successfully
      </p>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :is_windows, :boolean, required: true

  defp manual_config(assigns) do
    ~H"""
    <div class="space-y-6">
      <div :if={not @is_windows} class="bg-base-200 rounded-xl p-5">
        <h3 class="font-medium text-base mb-3">Setup Instructions</h3>
        <p class="text-sm text-base-content/70 mb-4">
          To enable the TSW API on your Windows PC running Train Sim World:
        </p>
        <ol class="text-sm text-base-content/80 space-y-3 list-none">
          <li class="flex gap-3">
            <span class="flex-shrink-0 w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              1
            </span>
            <span class="pt-0.5">Open Steam and go to your Library</span>
          </li>
          <li class="flex gap-3">
            <span class="flex-shrink-0 w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              2
            </span>
            <span class="pt-0.5">Right-click on Train Sim World 6 and select Properties</span>
          </li>
          <li class="flex gap-3">
            <span class="flex-shrink-0 w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              3
            </span>
            <span class="pt-0.5">
              In the General tab, add
              <code class="bg-base-300 px-1.5 py-0.5 rounded font-mono text-xs">-HTTPAPI</code>
              to Launch Options
            </span>
          </li>
          <li class="flex gap-3">
            <span class="flex-shrink-0 w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              4
            </span>
            <span class="pt-0.5">Start Train Sim World 6</span>
          </li>
          <li class="flex gap-3">
            <span class="flex-shrink-0 w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              5
            </span>
            <span class="pt-0.5">
              Find the API key in:<br />
              <code class="bg-base-300 px-1.5 py-0.5 rounded font-mono text-xs break-all inline-block mt-1">
                Documents\My Games\TrainSimWorld6\Saved\Config\CommAPIKey.txt
              </code>
            </span>
          </li>
          <li class="flex gap-3">
            <span class="flex-shrink-0 w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              6
            </span>
            <span class="pt-0.5">Enter the URL and API key below</span>
          </li>
        </ol>
      </div>

      <div :if={@is_windows} class="bg-base-200 rounded-xl p-4">
        <p class="text-sm text-base-content/70">
          Enter the connection details manually. Use this if you're connecting to a remote PC
          running Train Sim World.
        </p>
      </div>

      <.input field={@form[:url]} type="text" label="API URL" placeholder="http://localhost:31270" />

      <.input
        field={@form[:api_key]}
        type="text"
        label="API Key"
        placeholder="Your API key from CommAPIKey.txt"
      />
    </div>
    """
  end

  defp status_dot_color(status) do
    case status do
      :connected -> "bg-success"
      :connecting -> "bg-info animate-pulse"
      :error -> "bg-error"
      :needs_config -> "bg-warning"
      :disconnected -> "bg-base-content/20"
    end
  end

  defp status_alert_class(status) do
    case status do
      :connected -> "alert-success"
      :connecting -> "alert-info"
      :error -> "alert-error"
      :needs_config -> "alert-warning"
      :disconnected -> ""
    end
  end

  defp status_title(status) do
    case status do
      :connected -> "Connected"
      :connecting -> "Connecting..."
      :error -> "Connection Error"
      :needs_config -> "Configuration Required"
      :disconnected -> "Disconnected"
    end
  end

  defp status_message(%{status: :connected}) do
    "Successfully connected to Train Sim World API"
  end

  defp status_message(%{status: :connecting}) do
    "Establishing connection to simulator..."
  end

  defp status_message(%{status: :error, last_error: :invalid_key}) do
    "Invalid API key. Please check your configuration."
  end

  defp status_message(%{status: :error, last_error: :connection_failed}) do
    "Could not connect to the simulator. Make sure Train Sim World is running with -HTTPAPI flag."
  end

  defp status_message(%{status: :error, last_error: :timeout}) do
    "Connection timed out. Is Train Sim World running?"
  end

  defp status_message(%{status: :error}) do
    "An error occurred. Please check your configuration and try again."
  end

  defp status_message(%{status: :needs_config}) do
    "Please configure the simulator connection below."
  end

  defp status_message(%{status: :disconnected}) do
    "Not connected to simulator."
  end
end
