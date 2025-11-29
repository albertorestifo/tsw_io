defmodule TswIoWeb.ConfigurationListLive do
  @moduledoc """
  LiveView for listing and managing configurations.

  Displays all saved configurations and highlights those currently
  applied to connected devices.
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents

  alias TswIo.Hardware
  alias TswIo.Serial.Connection

  @impl true
  def mount(_params, _session, socket) do
    configurations = Hardware.list_configurations(preload: [:inputs])

    socket =
      socket
      |> assign(:configurations, configurations)
      |> assign(:show_apply_modal, false)
      |> assign(:apply_config, nil)
      |> assign(:show_delete_modal, false)
      |> assign(:delete_config, nil)

    {:ok, socket}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, :nav_devices, devices)}
  end

  @impl true
  def handle_info({:simulator_status_changed, status}, socket) do
    {:noreply, assign(socket, :nav_simulator_status, status)}
  end

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

  @impl true
  def handle_event("show_apply_modal", %{"config-id" => config_id_str}, socket) do
    {config_id, _} = Integer.parse(config_id_str)
    config = Enum.find(socket.assigns.configurations, &(&1.config_id == config_id))

    {:noreply,
     socket
     |> assign(:show_apply_modal, true)
     |> assign(:apply_config, config)}
  end

  @impl true
  def handle_event("close_apply_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_apply_modal, false)
     |> assign(:apply_config, nil)}
  end

  @impl true
  def handle_event("apply_to_device", %{"port" => port}, socket) do
    config = socket.assigns.apply_config

    case Hardware.apply_configuration(port, config.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Applying configuration to #{port}...")
         |> assign(:show_apply_modal, false)
         |> assign(:apply_config, nil)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to apply configuration: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("show_delete_modal", %{"config-id" => config_id_str}, socket) do
    {config_id, _} = Integer.parse(config_id_str)
    config = Enum.find(socket.assigns.configurations, &(&1.config_id == config_id))

    {:noreply,
     socket
     |> assign(:show_delete_modal, true)
     |> assign(:delete_config, config)}
  end

  @impl true
  def handle_event("close_delete_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:delete_config, nil)}
  end

  @impl true
  def handle_event("confirm_delete", _, socket) do
    config = socket.assigns.delete_config

    case Hardware.delete_device(config) do
      {:ok, _} ->
        configurations = Hardware.list_configurations(preload: [:inputs])

        {:noreply,
         socket
         |> put_flash(:info, "Configuration \"#{config.name}\" deleted")
         |> assign(:configurations, configurations)
         |> assign(:show_delete_modal, false)
         |> assign(:delete_config, nil)}

      {:error, :configuration_active} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot delete: configuration is active on a connected device")
         |> assign(:show_delete_modal, false)
         |> assign(:delete_config, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete: #{inspect(reason)}")
         |> assign(:show_delete_modal, false)
         |> assign(:delete_config, nil)}
    end
  end

  @impl true
  def render(assigns) do
    connected_devices = Enum.filter(assigns.nav_devices, &(&1.status == :connected))
    active_config_ids = MapSet.new(connected_devices, & &1.device_config_id)

    assigns =
      assigns
      |> assign(:connected_devices, connected_devices)
      |> assign(:active_config_ids, active_config_ids)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.nav_header
        devices={@nav_devices}
        simulator_status={@nav_simulator_status}
        dropdown_open={@nav_dropdown_open}
        scanning={@nav_scanning}
      />

      <main class="flex-1 p-4 sm:p-8">
        <div class="max-w-2xl mx-auto">
          <header class="mb-8 flex items-center justify-between">
            <div>
              <h1 class="text-2xl font-semibold">Configurations</h1>
              <p class="text-sm text-base-content/70 mt-1">
                Manage device configurations
              </p>
            </div>
            <.link navigate={~p"/configurations/new"} class="btn btn-primary">
              <.icon name="hero-plus" class="w-4 h-4" /> New Configuration
            </.link>
          </header>

          <.empty_state :if={Enum.empty?(@configurations)} />

          <div :if={not Enum.empty?(@configurations)} class="space-y-4">
            <.configuration_card
              :for={config <- @configurations}
              config={config}
              active={MapSet.member?(@active_config_ids, config.config_id)}
              connected_devices={@connected_devices}
            />
          </div>
        </div>
      </main>

      <.apply_modal
        :if={@show_apply_modal}
        config={@apply_config}
        connected_devices={@connected_devices}
      />

      <.delete_modal
        :if={@show_delete_modal}
        config={@delete_config}
        active={MapSet.member?(@active_config_ids, @delete_config.config_id)}
      />
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <.icon name="hero-cog-6-tooth" class="w-16 h-16 text-base-content/20" />
      <h2 class="mt-6 text-xl font-semibold">No Configurations</h2>
      <p class="mt-2 text-base-content/70 max-w-sm">
        Create a configuration to set up inputs for your TWS devices.
      </p>
      <.link navigate={~p"/configurations/new"} class="btn btn-primary mt-6">
        <.icon name="hero-plus" class="w-4 h-4" /> Create Configuration
      </.link>
    </div>
    """
  end

  attr :config, :map, required: true
  attr :active, :boolean, required: true
  attr :connected_devices, :list, required: true

  defp configuration_card(assigns) do
    input_count = length(assigns.config.inputs)
    assigns = assign(assigns, :input_count, input_count)

    ~H"""
    <div class={[
      "rounded-xl p-5 transition-colors",
      if(@active,
        do: "border-2 border-success bg-success/5",
        else: "border border-base-300 bg-base-200/50"
      )
    ]}>
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <h3 class="font-medium truncate">{@config.name}</h3>
            <span
              :if={@active}
              class="badge badge-success badge-sm flex items-center gap-1"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-success-content animate-pulse" /> Active
            </span>
          </div>
          <p :if={@config.description} class="text-sm text-base-content/70 mt-1 line-clamp-2">
            {@config.description}
          </p>
          <div class="mt-2 flex items-center gap-4 text-xs text-base-content/60">
            <span class="font-mono">ID: {@config.config_id}</span>
            <span>{input_count_text(@input_count)}</span>
          </div>
        </div>

        <div class="flex items-center gap-1 flex-shrink-0">
          <button
            :if={not @active and not Enum.empty?(@connected_devices)}
            type="button"
            phx-click="show_apply_modal"
            phx-value-config-id={@config.config_id}
            class="btn btn-outline btn-sm"
          >
            Apply
          </button>
          <.link
            navigate={~p"/configurations/#{@config.config_id}"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-pencil" class="w-4 h-4" />
          </.link>
          <button
            type="button"
            phx-click="show_delete_modal"
            phx-value-config-id={@config.config_id}
            class="btn btn-ghost btn-sm text-error hover:bg-error/10"
            disabled={@active}
            aria-label="Delete configuration"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :config, :map, required: true
  attr :connected_devices, :list, required: true

  defp apply_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="fixed inset-0 bg-black/50" phx-click="close_apply_modal" />
      <div class="relative bg-base-100 rounded-xl shadow-xl max-w-md w-full p-6">
        <h3 class="text-lg font-semibold mb-4">Apply Configuration</h3>
        <p class="text-sm text-base-content/70 mb-6">
          Select a device to apply "<span class="font-medium">{@config.name}</span>" to:
        </p>

        <div class="space-y-2">
          <button
            :for={device <- @connected_devices}
            type="button"
            phx-click="apply_to_device"
            phx-value-port={device.port}
            class="w-full flex items-center gap-3 p-3 rounded-lg border border-base-300 hover:bg-base-200 transition-colors text-left"
          >
            <span class="w-2 h-2 rounded-full bg-success" />
            <div class="min-w-0 flex-1">
              <p class="font-medium truncate">{device.port}</p>
              <p :if={device.device_version} class="text-xs text-base-content/60">
                v{device.device_version}
              </p>
            </div>
          </button>
        </div>

        <div class="mt-6 flex justify-end">
          <button type="button" phx-click="close_apply_modal" class="btn btn-ghost">
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :config, :map, required: true
  attr :active, :boolean, required: true

  defp delete_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="fixed inset-0 bg-black/50" phx-click="close_delete_modal" />
      <div class="relative bg-base-100 rounded-xl shadow-xl max-w-md w-full p-6">
        <h3 class="text-lg font-semibold mb-4 text-error">Delete Configuration</h3>

        <div :if={@active} class="alert alert-warning mb-4">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
          <span class="text-sm">This configuration is currently active on a connected device.</span>
        </div>

        <p class="text-sm text-base-content/70 mb-6">
          Are you sure you want to delete "<span class="font-medium">{@config.name}</span>"?
          This will permanently delete the configuration and all its inputs and calibration data.
        </p>

        <div class="flex justify-end gap-2">
          <button type="button" phx-click="close_delete_modal" class="btn btn-ghost">
            Cancel
          </button>
          <button
            :if={not @active}
            type="button"
            phx-click="confirm_delete"
            class="btn btn-error"
          >
            <.icon name="hero-trash" class="w-4 h-4" /> Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp input_count_text(0), do: "No inputs"
  defp input_count_text(1), do: "1 input"
  defp input_count_text(n), do: "#{n} inputs"
end
