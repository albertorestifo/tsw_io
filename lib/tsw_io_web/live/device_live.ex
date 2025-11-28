defmodule TswIoWeb.DeviceLive do
  use TswIoWeb, :live_view

  alias TswIo.Serial.Connection

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Connection.subscribe()
    end

    devices = Connection.list_devices()

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:dropdown_open, false)
     |> assign(:scanning, false)}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, :devices, devices)}
  end

  @impl true
  def handle_event("toggle_dropdown", _, socket) do
    {:noreply, assign(socket, :dropdown_open, !socket.assigns.dropdown_open)}
  end

  @impl true
  def handle_event("close_dropdown", _, socket) do
    {:noreply, assign(socket, :dropdown_open, false)}
  end

  @impl true
  def handle_event("scan", _, socket) do
    Connection.scan()
    {:noreply, assign(socket, :scanning, true)}
  end

  @impl true
  def handle_event("disconnect", %{"port" => port}, socket) do
    Connection.disconnect(port)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.status_bar
        devices={@devices}
        dropdown_open={@dropdown_open}
        scanning={@scanning}
      />

      <main class="flex-1 p-8">
        <.main_content devices={@devices} />
      </main>
    </div>
    """
  end

  # Status Bar Component
  attr :devices, :list, required: true
  attr :dropdown_open, :boolean, required: true
  attr :scanning, :boolean, required: true

  defp status_bar(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-300 px-4 sticky top-0 z-50">
      <div class="flex-1">
        <a href="/" class="text-lg font-semibold">TWS IO</a>
      </div>

      <div class="flex-none flex items-center gap-4">
        <div class="relative">
          <button
            phx-click="toggle_dropdown"
            class="flex items-center gap-2 px-3 py-2 rounded-lg bg-base-200 hover:bg-base-300 transition-colors duration-150"
            aria-expanded={@dropdown_open}
            aria-haspopup="menu"
          >
            <span class={["w-2 h-2 rounded-full", status_color(@devices)]} />
            <span class="text-sm font-medium hidden sm:inline">
              {device_count_text(@devices)}
            </span>
            <span class="text-sm font-medium sm:hidden">
              {connected_count(@devices)}
            </span>
            <.icon
              name="hero-chevron-down-solid"
              class={"w-4 h-4 transition-transform duration-200 #{if @dropdown_open, do: "rotate-180", else: ""}"}
            />
          </button>

          <.device_dropdown
            :if={@dropdown_open}
            devices={@devices}
            scanning={@scanning}
          />
        </div>

        <%!-- Theme toggle placeholder --%>
      </div>
    </header>
    """
  end

  # Device Dropdown Component
  attr :devices, :list, required: true
  attr :scanning, :boolean, required: true

  defp device_dropdown(assigns) do
    ~H"""
    <div
      class="absolute top-full right-0 mt-1 w-80 bg-base-100 border border-base-300 rounded-xl shadow-xl z-50"
      phx-click-away="close_dropdown"
    >
      <div class="p-4 border-b border-base-300">
        <button
          phx-click="scan"
          disabled={@scanning}
          class="btn btn-primary btn-sm w-full"
        >
          <.icon
            :if={@scanning}
            name="hero-arrow-path"
            class="w-4 h-4 animate-spin"
          />
          <.icon
            :if={!@scanning}
            name="hero-magnifying-glass"
            class="w-4 h-4"
          />
          {if @scanning, do: "Scanning...", else: "Scan for Devices"}
        </button>
      </div>

      <div class="max-h-80 overflow-y-auto">
        <.empty_device_list :if={Enum.empty?(@devices)} />

        <.device_list_item
          :for={device <- @devices}
          device={device}
        />
      </div>
    </div>
    """
  end

  defp empty_device_list(assigns) do
    ~H"""
    <div class="p-8 text-center">
      <.icon name="hero-signal-slash" class="w-8 h-8 mx-auto text-base-content/30" />
      <p class="mt-2 text-sm text-base-content/70">No devices found</p>
      <p class="text-xs text-base-content/50">Click scan to discover devices</p>
    </div>
    """
  end

  attr :device, :map, required: true

  defp device_list_item(assigns) do
    ~H"""
    <div class="px-4 py-3 border-b border-base-300 last:border-b-0 hover:bg-base-200/50">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2 min-w-0">
          <span class={["w-2 h-2 rounded-full flex-shrink-0", device_status_color(@device.status)]} />
          <span class="text-sm font-medium truncate">{@device.port}</span>
        </div>
        <button
          :if={@device.status == :connected}
          phx-click="disconnect"
          phx-value-port={@device.port}
          class="btn btn-ghost btn-xs text-error hover:bg-error/10"
          aria-label={"Disconnect from #{@device.port}"}
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>
      <div class="mt-1 text-xs text-base-content/60 pl-4">
        <span :if={@device.device_version}>v{@device.device_version}</span>
        <span :if={@device.device_version}> · </span>
        <span class="capitalize">{@device.status}</span>
      </div>
    </div>
    """
  end

  # Main Content Component
  attr :devices, :list, required: true

  defp main_content(assigns) do
    connected_devices = Enum.filter(assigns.devices, &(&1.status == :connected))
    assigns = assign(assigns, :connected_devices, connected_devices)

    ~H"""
    <div class="max-w-2xl mx-auto">
      <.no_devices_state :if={Enum.empty?(@connected_devices)} />
      <.device_config_state :if={length(@connected_devices) > 0} device={hd(@connected_devices)} />
    </div>
    """
  end

  defp no_devices_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <.icon name="hero-signal-slash" class="w-16 h-16 text-base-content/20" />
      <h2 class="mt-6 text-xl font-semibold">No Devices Connected</h2>
      <p class="mt-2 text-base-content/70 max-w-sm">
        Connect a TWS device to get started. Use the status bar to scan for available devices.
      </p>
    </div>
    """
  end

  attr :device, :map, required: true

  defp device_config_state(assigns) do
    has_config = assigns.device.device_config_id != nil
    assigns = assign(assigns, :has_config, has_config)

    ~H"""
    <div>
      <header class="mb-8">
        <h1 class="text-2xl font-semibold">Device Configuration</h1>
        <p class="text-sm text-base-content/70 mt-1">
          {@device.port}
          <span :if={@device.device_version}> · v{@device.device_version}</span>
        </p>
      </header>

      <.unknown_config_state :if={!@has_config} />
      <.known_config_state :if={@has_config} device={@device} />
    </div>
    """
  end

  defp unknown_config_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 text-center bg-base-200/50 rounded-xl">
      <.icon name="hero-wrench-screwdriver" class="w-12 h-12 text-base-content/30" />
      <h3 class="mt-4 text-lg font-medium">Configure This Device</h3>
      <p class="mt-2 text-sm text-base-content/70 max-w-sm">
        This device hasn't been configured yet. Set up inputs and outputs to start using it.
      </p>
      <.link
        navigate={~p"/devices/#{URI.encode_www_form(@device.port)}/config"}
        class="btn btn-primary mt-6"
      >
        <.icon name="hero-plus" class="w-4 h-4" /> Create Configuration
      </.link>
    </div>
    """
  end

  attr :device, :map, required: true

  defp known_config_state(assigns) do
    ~H"""
    <div class="bg-base-200/50 rounded-xl p-6">
      <div class="flex items-center justify-between">
        <p class="text-sm text-base-content/70">
          Configuration ID: <span class="font-mono">{@device.device_config_id}</span>
        </p>
        <.link
          navigate={~p"/devices/#{URI.encode_www_form(@device.port)}/config"}
          class="btn btn-outline btn-sm"
        >
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Manage Configuration
        </.link>
      </div>
    </div>
    """
  end

  # Helper functions

  defp status_color(devices) do
    connected = Enum.filter(devices, &(&1.status == :connected))
    discovering = Enum.filter(devices, &(&1.status in [:connecting, :discovering]))
    failed = Enum.filter(devices, &(&1.status == :failed))

    cond do
      Enum.empty?(devices) -> "bg-base-content/20"
      length(connected) > 0 and Enum.empty?(discovering) -> "bg-success"
      length(discovering) > 0 -> "bg-info animate-pulse"
      length(failed) > 0 -> "bg-warning"
      true -> "bg-base-content/40"
    end
  end

  defp device_status_color(status) do
    case status do
      :connected -> "bg-success"
      :connecting -> "bg-info animate-pulse"
      :discovering -> "bg-info animate-pulse"
      :disconnecting -> "bg-warning"
      :failed -> "bg-error"
      _ -> "bg-base-content/20"
    end
  end

  defp device_count_text(devices) do
    connected = Enum.count(devices, &(&1.status == :connected))

    case connected do
      0 -> "No Devices"
      1 -> "1 Device"
      n -> "#{n} Devices"
    end
  end

  defp connected_count(devices) do
    Enum.count(devices, &(&1.status == :connected))
  end
end
