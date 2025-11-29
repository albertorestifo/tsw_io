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

    {:ok, assign(socket, :configurations, configurations)}
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
  def render(assigns) do
    connected_devices = Enum.filter(assigns.nav_devices, &(&1.status == :connected))
    active_config_ids = MapSet.new(connected_devices, & &1.device_config_id)

    assigns = assign(assigns, :active_config_ids, active_config_ids)

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
            />
          </div>
        </div>
      </main>
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

  defp configuration_card(assigns) do
    input_count = length(assigns.config.inputs)
    assigns = assign(assigns, :input_count, input_count)

    ~H"""
    <div class={[
      "rounded-xl transition-colors group",
      if(@active,
        do: "border-2 border-success bg-success/5",
        else: "border border-base-300 bg-base-200/50 hover:bg-base-200"
      )
    ]}>
      <div class="flex items-start justify-between gap-4 p-5">
        <.link
          navigate={~p"/configurations/#{@config.config_id}"}
          class="flex-1 cursor-pointer"
        >
          <div class="flex items-center gap-2">
            <h3 class="font-medium truncate group-hover:text-primary transition-colors">
              {@config.name}
            </h3>
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
        </.link>

        <.icon
          name="hero-chevron-right"
          class="w-5 h-5 text-base-content/30 group-hover:text-base-content/50 transition-colors flex-shrink-0"
        />
      </div>
    </div>
    """
  end

  defp input_count_text(0), do: "No inputs"
  defp input_count_text(1), do: "1 input"
  defp input_count_text(n), do: "#{n} inputs"
end
