defmodule TswIoWeb.NavHook do
  @moduledoc """
  LiveView hook for persistent navigation with status indicators.

  Subscribes to device, simulator, firmware update, and app version status on mount.
  This is used with `on_mount` in the router to provide shared
  navigation state across all LiveViews.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias TswIo.AppVersion
  alias TswIo.Firmware
  alias TswIo.Serial.Connection
  alias TswIo.Simulator

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Connection.subscribe()
      Simulator.subscribe()
      Firmware.subscribe_update_notifications()
      AppVersion.subscribe_update_notifications()
    end

    devices = Connection.list_devices()
    simulator_status = Simulator.get_status()
    firmware_update_status = Firmware.check_update_status()
    app_version_update_status = AppVersion.check_update_status()

    {:cont,
     socket
     |> assign(:nav_devices, devices)
     |> assign(:nav_simulator_status, simulator_status)
     |> assign(:nav_firmware_update, format_update_status(firmware_update_status))
     |> assign(:nav_app_version_update, format_update_status(app_version_update_status))
     |> assign(:nav_firmware_checking, false)
     |> assign(:nav_dropdown_open, false)
     |> assign(:nav_scanning, false)
     |> assign(:nav_current_path, "/")
     |> attach_hook(:nav_path_tracker, :handle_params, &handle_params/3)
     |> attach_hook(:nav_firmware_events, :handle_event, &handle_event/3)
     |> attach_hook(:nav_firmware_info, :handle_info, &handle_info/2)}
  end

  defp handle_params(_params, uri, socket) do
    path = URI.parse(uri).path
    {:cont, assign(socket, :nav_current_path, path)}
  end

  defp handle_event("dismiss_firmware_update", _params, socket) do
    Firmware.dismiss_update_notification()
    {:halt, socket}
  end

  defp handle_event("check_firmware_updates", _params, socket) do
    Firmware.trigger_update_check()
    {:halt, socket}
  end

  defp handle_event("dismiss_app_version_update", _params, socket) do
    AppVersion.dismiss_update_notification()
    {:halt, socket}
  end

  defp handle_event(_event, _params, socket) do
    {:cont, socket}
  end

  # Firmware update events
  defp handle_info({:firmware_update_available, version}, socket) do
    {:cont, assign(socket, :nav_firmware_update, %{available: true, version: version})}
  end

  defp handle_info(:firmware_update_dismissed, socket) do
    {:cont, assign(socket, :nav_firmware_update, nil)}
  end

  defp handle_info({:firmware_update_checking, checking}, socket) do
    {:cont, assign(socket, :nav_firmware_checking, checking)}
  end

  # App version update events
  defp handle_info({:app_version_update_available, version}, socket) do
    {:cont, assign(socket, :nav_app_version_update, %{available: true, version: version})}
  end

  defp handle_info(:app_version_update_dismissed, socket) do
    {:cont, assign(socket, :nav_app_version_update, nil)}
  end

  defp handle_info({:app_version_update_checking, _checking}, socket) do
    # We don't show a checking indicator for app version updates
    {:cont, socket}
  end

  defp handle_info(_msg, socket) do
    {:cont, socket}
  end

  defp format_update_status({:update_available, version}) do
    %{available: true, version: version}
  end

  defp format_update_status(:no_update), do: nil
end
