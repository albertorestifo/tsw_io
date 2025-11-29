defmodule TswIoWeb.NavComponents do
  @moduledoc """
  Shared navigation components for persistent header and breadcrumbs.
  """

  use Phoenix.Component
  use TswIoWeb, :verified_routes

  import TswIoWeb.CoreComponents

  @doc """
  Persistent navigation header with status indicators.

  The header content is constrained to max-w-2xl to align with
  the main content area, while the background extends full-width.
  """
  attr :devices, :list, required: true
  attr :simulator_status, :map, required: true
  attr :dropdown_open, :boolean, default: false
  attr :scanning, :boolean, default: false

  def nav_header(assigns) do
    ~H"""
    <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50 px-4 sm:px-8">
      <div class="max-w-2xl mx-auto py-3 flex items-center">
        <div class="flex-1">
          <.link navigate={~p"/"} class="text-lg font-semibold">TWS IO</.link>
        </div>

        <div class="flex-none flex items-center gap-3">
          <.link
            navigate={~p"/simulator/config"}
            class="flex items-center gap-2 px-3 py-2 rounded-lg bg-base-200 hover:bg-base-300 transition-colors duration-150"
            title="Simulator Connection"
          >
            <span class={["w-2 h-2 rounded-full", simulator_status_color(@simulator_status.status)]} />
            <span class="text-sm font-medium hidden sm:inline">Simulator</span>
          </.link>

          <div class="relative">
            <button
              phx-click="nav_toggle_dropdown"
              class="flex items-center gap-2 px-3 py-2 rounded-lg bg-base-200 hover:bg-base-300 transition-colors duration-150"
              aria-expanded={@dropdown_open}
              aria-haspopup="menu"
            >
              <span class={["w-2 h-2 rounded-full", devices_status_color(@devices)]} />
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

            <.device_dropdown :if={@dropdown_open} devices={@devices} scanning={@scanning} />
          </div>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Breadcrumb navigation component.

  Items should be a list of maps with :label and optional :path keys.
  The last item typically has no path and represents the current page.

  ## Examples

      <.breadcrumb items={[
        %{label: "Home", path: ~p"/"},
        %{label: "Configuration"}
      ]} />
  """
  attr :items, :list, required: true, doc: "List of %{label: string, path: string | nil}"

  def breadcrumb(assigns) do
    ~H"""
    <nav :if={length(@items) > 1} class="bg-base-200/50 border-b border-base-300 px-4 sm:px-8">
      <div class="max-w-2xl mx-auto py-2">
        <ol class="flex items-center gap-2 text-sm">
          <li :for={{item, index} <- Enum.with_index(@items)} class="flex items-center gap-2">
            <.icon
              :if={index > 0}
              name="hero-chevron-right-mini"
              class="w-4 h-4 text-base-content/40"
            />

            <.link
              :if={item[:path]}
              navigate={item.path}
              class="text-base-content/70 hover:text-base-content transition-colors"
            >
              {item.label}
            </.link>

            <span :if={!item[:path]} class="text-base-content font-medium">
              {item.label}
            </span>
          </li>
        </ol>
      </div>
    </nav>
    """
  end

  # Device dropdown component
  attr :devices, :list, required: true
  attr :scanning, :boolean, default: false

  defp device_dropdown(assigns) do
    ~H"""
    <div
      class="absolute top-full right-0 mt-1 w-80 bg-base-100 border border-base-300 rounded-xl shadow-xl z-50"
      phx-click-away="nav_close_dropdown"
    >
      <div class="p-4 border-b border-base-300">
        <button
          phx-click="nav_scan_devices"
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
        <.device_list_item :for={device <- @devices} device={device} />
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
          phx-click="nav_disconnect_device"
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

  # Helper functions

  defp devices_status_color(devices) do
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

  defp simulator_status_color(status) do
    case status do
      :connected -> "bg-success"
      :connecting -> "bg-info animate-pulse"
      :error -> "bg-error"
      :needs_config -> "bg-warning"
      :disconnected -> "bg-base-content/20"
    end
  end
end
