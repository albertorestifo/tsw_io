defmodule TswIoWeb.FirmwareLive do
  @moduledoc """
  LiveView for firmware management.

  Allows users to:
  - Check for firmware updates from GitHub
  - Download firmware for specific board types
  - Upload firmware to connected devices
  - View upload history
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents

  alias TswIo.Firmware
  alias TswIo.Firmware.{BoardConfig, FirmwareFile}
  alias TswIo.Serial.Connection

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Firmware.subscribe_uploads()
    end

    releases = Firmware.list_releases(preload: [:firmware_files])
    upload_history = Firmware.list_upload_history(limit: 10, preload: [:firmware_file])
    current_upload = Firmware.current_upload()

    {:ok,
     socket
     |> assign(:releases, releases)
     |> assign(:upload_history, upload_history)
     |> assign(:current_upload, current_upload)
     |> assign(:checking_updates, false)
     |> assign(:downloading, nil)
     |> assign(:selected_device, nil)
     |> assign(:selected_board_type, nil)
     |> assign(:show_upload_modal, false)
     |> assign(:upload_progress, nil)
     |> assign(:upload_error, nil)}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, :nav_devices, devices)}
  end

  @impl true
  def handle_info({:simulator_status_changed, status}, socket) do
    {:noreply, assign(socket, :nav_simulator_status, status)}
  end

  # Upload events
  @impl true
  def handle_info({:upload_started, _upload_id, _port, _board_type}, socket) do
    {:noreply,
     socket
     |> assign(:upload_progress, %{percent: 0, message: "Starting upload..."})
     |> assign(:current_upload, Firmware.current_upload())}
  end

  @impl true
  def handle_info({:upload_progress, _upload_id, percent, message}, socket) do
    {:noreply, assign(socket, :upload_progress, %{percent: percent, message: message})}
  end

  @impl true
  def handle_info({:upload_completed, _upload_id, duration_ms}, socket) do
    {:noreply,
     socket
     |> assign(:current_upload, nil)
     |> assign(:upload_progress, nil)
     |> assign(:show_upload_modal, false)
     |> assign(:upload_history, Firmware.list_upload_history(limit: 10, preload: [:firmware_file]))
     |> put_flash(:info, "Firmware uploaded successfully in #{duration_ms}ms")}
  end

  @impl true
  def handle_info({:upload_failed, _upload_id, _reason, message}, socket) do
    {:noreply,
     socket
     |> assign(:current_upload, nil)
     |> assign(:upload_progress, nil)
     |> assign(:upload_error, message)
     |> assign(:upload_history, Firmware.list_upload_history(limit: 10, preload: [:firmware_file]))}
  end

  # Nav events
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

  # Firmware events
  @impl true
  def handle_event("check_updates", _, socket) do
    socket = assign(socket, :checking_updates, true)

    case Firmware.check_for_updates() do
      {:ok, _new_releases} ->
        releases = Firmware.list_releases(preload: [:firmware_files])

        {:noreply,
         socket
         |> assign(:releases, releases)
         |> assign(:checking_updates, false)
         |> put_flash(:info, "Firmware releases updated")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:checking_updates, false)
         |> put_flash(:error, "Failed to check for updates: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("download_firmware", %{"file-id" => file_id_str}, socket) do
    file_id = String.to_integer(file_id_str)
    socket = assign(socket, :downloading, file_id)

    case Firmware.download_firmware(file_id) do
      {:ok, _file} ->
        releases = Firmware.list_releases(preload: [:firmware_files])

        {:noreply,
         socket
         |> assign(:releases, releases)
         |> assign(:downloading, nil)
         |> put_flash(:info, "Firmware downloaded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:downloading, nil)
         |> put_flash(:error, "Download failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("show_upload_modal", %{"port" => port}, socket) do
    {:noreply,
     socket
     |> assign(:selected_device, port)
     |> assign(:selected_board_type, nil)
     |> assign(:show_upload_modal, true)
     |> assign(:upload_error, nil)}
  end

  @impl true
  def handle_event("close_upload_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_upload_modal, false)
     |> assign(:upload_error, nil)}
  end

  @impl true
  def handle_event("select_board_type", %{"board_type" => board_type}, socket) do
    {:noreply, assign(socket, :selected_board_type, String.to_existing_atom(board_type))}
  end

  @impl true
  def handle_event("start_upload", _, socket) do
    port = socket.assigns.selected_device
    board_type = socket.assigns.selected_board_type

    with {:ok, release} <- Firmware.get_latest_release(preload: [:firmware_files]),
         {:ok, file} <- find_downloaded_file(release, board_type),
         {:ok, _upload_id} <- Firmware.start_upload(port, board_type, file.id) do
      {:noreply, assign(socket, :upload_error, nil)}
    else
      {:error, :not_found} ->
        {:noreply, assign(socket, :upload_error, "No firmware releases available. Check for updates first.")}

      {:error, :firmware_not_downloaded} ->
        {:noreply, assign(socket, :upload_error, "Please download the firmware first.")}

      {:error, reason} ->
        {:noreply, assign(socket, :upload_error, "Failed to start upload: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel_upload", _, socket) do
    case socket.assigns.current_upload do
      %{upload_id: upload_id} ->
        Firmware.cancel_upload(upload_id)
        {:noreply, socket}

      nil ->
        {:noreply, socket}
    end
  end

  defp find_downloaded_file(release, board_type) do
    case Enum.find(release.firmware_files, &(&1.board_type == board_type && FirmwareFile.downloaded?(&1))) do
      nil -> {:error, :firmware_not_downloaded}
      file -> {:ok, file}
    end
  end

  @impl true
  def render(assigns) do
    connected_devices =
      assigns.nav_devices
      |> Enum.filter(&(&1.status == :connected))

    assigns = assign(assigns, :connected_devices, connected_devices)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.nav_header
        devices={@nav_devices}
        simulator_status={@nav_simulator_status}
        dropdown_open={@nav_dropdown_open}
        scanning={@nav_scanning}
        current_path={@nav_current_path}
      />

      <main class="flex-1 p-4 sm:p-8">
        <div class="max-w-4xl mx-auto">
          <header class="mb-8 flex items-center justify-between">
            <div>
              <h1 class="text-2xl font-semibold">Firmware</h1>
              <p class="text-sm text-base-content/70 mt-1">
                Download and upload firmware to your devices
              </p>
            </div>
            <button
              phx-click="check_updates"
              disabled={@checking_updates}
              class="btn btn-primary"
            >
              <.icon
                name="hero-arrow-path"
                class={if @checking_updates, do: "w-4 h-4 animate-spin", else: "w-4 h-4"}
              />
              {if @checking_updates, do: "Checking...", else: "Check for Updates"}
            </button>
          </header>

          <.empty_releases :if={Enum.empty?(@releases)} checking={@checking_updates} />

          <div :if={not Enum.empty?(@releases)} class="space-y-8">
            <section>
              <h2 class="text-lg font-medium mb-4">Available Releases</h2>
              <div class="space-y-4">
                <.release_card
                  :for={release <- @releases}
                  release={release}
                  downloading={@downloading}
                />
              </div>
            </section>

            <section :if={not Enum.empty?(@connected_devices)}>
              <h2 class="text-lg font-medium mb-4">Connected Devices</h2>
              <div class="space-y-3">
                <.device_card
                  :for={device <- @connected_devices}
                  device={device}
                  current_upload={@current_upload}
                />
              </div>
            </section>

            <section :if={not Enum.empty?(@upload_history)}>
              <h2 class="text-lg font-medium mb-4">Upload History</h2>
              <.history_table history={@upload_history} />
            </section>
          </div>
        </div>
      </main>

      <.upload_modal
        :if={@show_upload_modal}
        device={@selected_device}
        board_type={@selected_board_type}
        releases={@releases}
        progress={@upload_progress}
        error={@upload_error}
        current_upload={@current_upload}
      />
    </div>
    """
  end

  defp empty_releases(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <.icon name="hero-cpu-chip" class="w-16 h-16 text-base-content/20" />
      <h2 class="mt-6 text-xl font-semibold">No Firmware Releases</h2>
      <p class="mt-2 text-base-content/70 max-w-sm">
        {if @checking, do: "Checking for updates...", else: "Click 'Check for Updates' to fetch available firmware versions from GitHub."}
      </p>
    </div>
    """
  end

  attr :release, :map, required: true
  attr :downloading, :any, required: true

  defp release_card(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl bg-base-200/50 p-5">
      <div class="flex items-start justify-between gap-4 mb-4">
        <div>
          <div class="flex items-center gap-2">
            <h3 class="font-medium">v{@release.version}</h3>
            <span class="badge badge-ghost badge-sm">{@release.tag_name}</span>
          </div>
          <p :if={@release.published_at} class="text-xs text-base-content/60 mt-1">
            Released {Calendar.strftime(@release.published_at, "%B %d, %Y")}
          </p>
        </div>
        <a
          :if={@release.release_url}
          href={@release.release_url}
          target="_blank"
          class="btn btn-ghost btn-xs"
        >
          <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" />
          View on GitHub
        </a>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
        <.board_file_button
          :for={file <- @release.firmware_files}
          file={file}
          downloading={@downloading == file.id}
        />
      </div>
    </div>
    """
  end

  attr :file, :map, required: true
  attr :downloading, :boolean, required: true

  defp board_file_button(assigns) do
    {:ok, config} = BoardConfig.get_config(assigns.file.board_type)
    downloaded = FirmwareFile.downloaded?(assigns.file)
    assigns = assign(assigns, config: config, downloaded: downloaded)

    ~H"""
    <button
      phx-click="download_firmware"
      phx-value-file-id={@file.id}
      disabled={@downloading || @downloaded}
      class={[
        "btn btn-sm justify-start",
        if(@downloaded, do: "btn-success", else: "btn-outline")
      ]}
    >
      <.icon
        :if={@downloading}
        name="hero-arrow-path"
        class="w-3 h-3 animate-spin"
      />
      <.icon
        :if={@downloaded && !@downloading}
        name="hero-check"
        class="w-3 h-3"
      />
      <.icon
        :if={!@downloaded && !@downloading}
        name="hero-arrow-down-tray"
        class="w-3 h-3"
      />
      <span class="truncate">{@config.name}</span>
    </button>
    """
  end

  attr :device, :map, required: true
  attr :current_upload, :any, required: true

  defp device_card(assigns) do
    uploading = assigns.current_upload && assigns.current_upload.port == assigns.device.port
    assigns = assign(assigns, :uploading, uploading)

    ~H"""
    <div class="border border-base-300 rounded-lg bg-base-200/50 p-4 flex items-center justify-between">
      <div class="flex items-center gap-3">
        <div class="w-2 h-2 rounded-full bg-success animate-pulse" />
        <div>
          <p class="font-mono text-sm">{@device.port}</p>
          <p class="text-xs text-base-content/60">
            Firmware v{@device.device_version || "unknown"}
          </p>
        </div>
      </div>
      <button
        :if={!@uploading}
        phx-click="show_upload_modal"
        phx-value-port={@device.port}
        class="btn btn-sm btn-outline"
      >
        <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
        Update Firmware
      </button>
      <span :if={@uploading} class="badge badge-warning">
        <.icon name="hero-arrow-path" class="w-3 h-3 animate-spin mr-1" />
        Uploading...
      </span>
    </div>
    """
  end

  attr :history, :list, required: true

  defp history_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm">
        <thead>
          <tr>
            <th>Port</th>
            <th>Board</th>
            <th>Status</th>
            <th>Duration</th>
            <th>Time</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @history}>
            <td class="font-mono text-xs">{entry.port}</td>
            <td>{entry.board_type}</td>
            <td>
              <.status_badge status={entry.status} />
            </td>
            <td>
              {if entry.duration_ms, do: "#{entry.duration_ms}ms", else: "-"}
            </td>
            <td class="text-xs text-base-content/60">
              {if entry.started_at, do: Calendar.strftime(entry.started_at, "%H:%M:%S"), else: "-"}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    {class, text} =
      case assigns.status do
        :completed -> {"badge-success", "Success"}
        :failed -> {"badge-error", "Failed"}
        :cancelled -> {"badge-warning", "Cancelled"}
        :started -> {"badge-info", "In Progress"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  attr :device, :string, required: true
  attr :board_type, :atom, required: true
  attr :releases, :list, required: true
  attr :progress, :map, required: true
  attr :error, :string, required: true
  attr :current_upload, :any, required: true

  defp upload_modal(assigns) do
    board_options = BoardConfig.select_options()
    uploading = assigns.current_upload != nil
    assigns = assign(assigns, board_options: board_options, uploading: uploading)

    ~H"""
    <div class="modal modal-open">
      <div class="modal-box">
        <button
          :if={!@uploading}
          phx-click="close_upload_modal"
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>

        <h3 class="font-bold text-lg">Update Firmware</h3>
        <p class="text-sm text-base-content/70 mt-1">
          Device: <span class="font-mono">{@device}</span>
        </p>

        <div :if={!@uploading} class="mt-4 space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Board Type</span>
            </label>
            <select
              phx-change="select_board_type"
              name="board_type"
              class="select select-bordered w-full"
            >
              <option value="" disabled selected={@board_type == nil}>
                Select your board type
              </option>
              <option
                :for={{name, value} <- @board_options}
                value={value}
                selected={@board_type == value}
              >
                {name}
              </option>
            </select>
            <label class="label">
              <span class="label-text-alt text-base-content/60">
                Make sure this matches your physical board
              </span>
            </label>
          </div>

          <div :if={@error} class="alert alert-error">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
            <span class="text-sm whitespace-pre-wrap">{@error}</span>
          </div>

          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
            <div class="text-sm">
              <p class="font-medium">Do not disconnect the device during upload</p>
              <p class="text-base-content/70">
                Interrupting the upload may corrupt the firmware.
              </p>
            </div>
          </div>
        </div>

        <div :if={@uploading} class="mt-4 space-y-4">
          <div class="text-center py-4">
            <.icon name="hero-cpu-chip" class="w-12 h-12 text-primary mx-auto animate-pulse" />
            <p class="mt-2 text-sm text-base-content/70">
              {@progress && @progress.message || "Uploading..."}
            </p>
          </div>

          <progress
            :if={@progress}
            class="progress progress-primary w-full"
            value={@progress.percent}
            max="100"
          >
          </progress>

          <p class="text-center text-xs text-base-content/60">
            Do not disconnect the device
          </p>
        </div>

        <div class="modal-action">
          <button
            :if={!@uploading}
            phx-click="close_upload_modal"
            class="btn btn-ghost"
          >
            Cancel
          </button>
          <button
            :if={!@uploading}
            phx-click="start_upload"
            disabled={@board_type == nil}
            class="btn btn-primary"
          >
            <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
            Start Upload
          </button>
          <button
            :if={@uploading}
            phx-click="cancel_upload"
            class="btn btn-error"
          >
            Cancel Upload
          </button>
        </div>
      </div>
      <div class="modal-backdrop bg-base-300/80" phx-click="close_upload_modal"></div>
    </div>
    """
  end
end
