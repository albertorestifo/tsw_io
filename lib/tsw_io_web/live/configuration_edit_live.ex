defmodule TswIoWeb.ConfigurationEditLive do
  @moduledoc """
  LiveView for editing a configuration.

  Supports both creating new configurations and editing existing ones.
  Configurations can be applied to any connected device.
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents

  alias TswIo.Hardware
  alias TswIo.Hardware.{ConfigId, Device, Input}
  alias TswIo.Hardware.Calibration.Session
  alias TswIo.Serial.Connection

  @impl true
  def mount(%{"config_id" => "new"}, _session, socket) do
    mount_new(socket)
  end

  @impl true
  def mount(%{"config_id" => config_id_str}, _session, socket) do
    case ConfigId.parse(config_id_str) do
      {:ok, config_id} ->
        mount_existing(socket, config_id)

      {:error, :invalid} ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid configuration ID")
         |> redirect(to: ~p"/")}
    end
  end

  defp mount_new(socket) do
    if connected?(socket) do
      Hardware.subscribe_configuration()
    end

    {:ok, device} = Hardware.create_device(%{name: "New Configuration"})
    changeset = Device.changeset(device, %{})

    {:ok,
     socket
     |> assign(:device, device)
     |> assign(:device_form, to_form(changeset))
     |> assign(:inputs, [])
     |> assign(:input_values, %{})
     |> assign(:new_mode, true)
     |> assign(:active_port, nil)
     |> assign(:modal_open, false)
     |> assign(:form, to_form(Input.changeset(%Input{}, %{input_type: :analog, sensitivity: 5})))
     |> assign(:applying, false)
     |> assign(:calibrating_input, nil)
     |> assign(:calibration_session_state, nil)
     |> assign(:show_apply_modal, false)
     |> assign(:show_delete_modal, false)}
  end

  defp mount_existing(socket, config_id) do
    case Hardware.get_device_by_config_id(config_id) do
      {:ok, device} ->
        if connected?(socket) do
          Hardware.subscribe_configuration()

          # Subscribe to input values for active port
          active_port = find_active_port(config_id)

          if active_port do
            Hardware.subscribe_input_values(active_port)
          end
        end

        {:ok, inputs} = Hardware.list_inputs(device.id)
        active_port = find_active_port(config_id)
        input_values = if active_port, do: Hardware.get_input_values(active_port), else: %{}
        changeset = Device.changeset(device, %{})

        {:ok,
         socket
         |> assign(:device, device)
         |> assign(:device_form, to_form(changeset))
         |> assign(:inputs, inputs)
         |> assign(:input_values, input_values)
         |> assign(:new_mode, false)
         |> assign(:active_port, active_port)
         |> assign(:modal_open, false)
         |> assign(
           :form,
           to_form(Input.changeset(%Input{}, %{input_type: :analog, sensitivity: 5}))
         )
         |> assign(:applying, false)
         |> assign(:calibrating_input, nil)
         |> assign(:calibration_session_state, nil)
         |> assign(:show_apply_modal, false)
         |> assign(:show_delete_modal, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Configuration not found")
         |> redirect(to: ~p"/")}
    end
  end

  defp find_active_port(config_id) do
    Connection.list_devices()
    |> Enum.find(&(&1.device_config_id == config_id && &1.status == :connected))
    |> then(fn
      nil -> nil
      device -> device.port
    end)
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

  # Device name/description editing
  @impl true
  def handle_event("validate_device", %{"device" => params}, socket) do
    changeset =
      socket.assigns.device
      |> Device.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :device_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_device", %{"device" => params}, socket) do
    case Hardware.update_device(socket.assigns.device, params) do
      {:ok, device} ->
        changeset = Device.changeset(device, %{})

        {:noreply,
         socket
         |> assign(:device, device)
         |> assign(:device_form, to_form(changeset))
         |> put_flash(:info, "Configuration saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, :device_form, to_form(changeset))}
    end
  end

  # Input management
  @impl true
  def handle_event("open_add_input_modal", _params, socket) do
    {:noreply, assign(socket, :modal_open, true)}
  end

  @impl true
  def handle_event("close_add_input_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_open, false)
     |> assign(:form, to_form(Input.changeset(%Input{}, %{input_type: :analog, sensitivity: 5})))}
  end

  @impl true
  def handle_event("validate_input", %{"input" => params}, socket) do
    changeset =
      %Input{}
      |> Input.changeset(Map.put(params, "device_id", socket.assigns.device.id))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("add_input", %{"input" => params}, socket) do
    case Hardware.create_input(socket.assigns.device.id, params) do
      {:ok, _input} ->
        {:ok, inputs} = Hardware.list_inputs(socket.assigns.device.id)

        {:noreply,
         socket
         |> assign(:inputs, inputs)
         |> assign(:modal_open, false)
         |> assign(
           :form,
           to_form(Input.changeset(%Input{}, %{input_type: :analog, sensitivity: 5}))
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_input", %{"id" => id}, socket) do
    case Hardware.delete_input(String.to_integer(id)) do
      {:ok, _input} ->
        {:ok, inputs} = Hardware.list_inputs(socket.assigns.device.id)
        {:noreply, assign(socket, :inputs, inputs)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete input")}
    end
  end

  # Apply configuration
  @impl true
  def handle_event("show_apply_modal", _params, socket) do
    {:noreply, assign(socket, :show_apply_modal, true)}
  end

  @impl true
  def handle_event("close_apply_modal", _params, socket) do
    {:noreply, assign(socket, :show_apply_modal, false)}
  end

  @impl true
  def handle_event("apply_to_device", %{"port" => port}, socket) do
    socket =
      socket
      |> assign(:applying, true)
      |> assign(:show_apply_modal, false)

    case Hardware.apply_configuration(port, socket.assigns.device.id) do
      {:ok, _config_id} ->
        {:noreply, socket}

      {:error, :no_inputs} ->
        {:noreply,
         socket
         |> assign(:applying, false)
         |> put_flash(:error, "Cannot apply empty configuration. Add at least one input.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:applying, false)
         |> put_flash(:error, "Failed to apply: #{inspect(reason)}")}
    end
  end

  # Delete configuration
  @impl true
  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  @impl true
  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  @impl true
  def handle_event("confirm_delete", _params, socket) do
    device = socket.assigns.device

    case Hardware.delete_device(device) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Configuration \"#{device.name}\" deleted")
         |> redirect(to: ~p"/")}

      {:error, :configuration_active} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot delete: configuration is active on a connected device")
         |> assign(:show_delete_modal, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete: #{inspect(reason)}")
         |> assign(:show_delete_modal, false)}
    end
  end

  # Calibration
  @impl true
  def handle_event("start_calibration", %{"id" => id}, socket) do
    input = Enum.find(socket.assigns.inputs, &(&1.id == String.to_integer(id)))

    if input && socket.assigns.active_port do
      Session.subscribe(input.id)
      {:noreply, assign(socket, :calibrating_input, input)}
    else
      {:noreply, put_flash(socket, :error, "Apply configuration to a device before calibrating")}
    end
  end

  # PubSub Event Handlers

  @impl true
  def handle_info({:calibration_result, {:ok, _calibration}}, socket) do
    {:ok, inputs} = Hardware.list_inputs(socket.assigns.device.id)

    {:noreply,
     socket
     |> assign(:inputs, inputs)
     |> assign(:calibrating_input, nil)
     |> put_flash(:info, "Calibration saved successfully")}
  end

  @impl true
  def handle_info({:calibration_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:calibrating_input, nil)
     |> put_flash(:error, "Calibration failed: #{inspect(reason)}")}
  end

  @impl true
  def handle_info(:calibration_cancelled, socket) do
    {:noreply, assign(socket, :calibrating_input, nil)}
  end

  @impl true
  def handle_info({:calibration_error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:calibrating_input, nil)
     |> put_flash(:error, "Failed to start calibration: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({event, state}, socket)
      when event in [:session_started, :step_changed, :sample_collected] do
    {:noreply, assign(socket, :calibration_session_state, state)}
  end

  @impl true
  def handle_info({:configuration_applied, port, device, _config_id}, socket) do
    # Subscribe to input values for the new active port
    Hardware.subscribe_input_values(port)

    {:noreply,
     socket
     |> assign(:device, device)
     |> assign(:new_mode, false)
     |> assign(:active_port, port)
     |> assign(:applying, false)
     |> put_flash(:info, "Configuration applied successfully")}
  end

  @impl true
  def handle_info({:configuration_failed, _port, _device_id, reason}, socket) do
    message =
      case reason do
        :timeout -> "Configuration timed out - device did not respond"
        :device_rejected -> "Device rejected the configuration"
        :no_inputs -> "Cannot apply empty configuration"
        _ -> "Failed to apply configuration"
      end

    {:noreply,
     socket
     |> assign(:applying, false)
     |> put_flash(:error, message)}
  end

  @impl true
  def handle_info({:input_value_updated, _port, pin, value}, socket) do
    new_values = Map.put(socket.assigns.input_values, pin, value)
    {:noreply, assign(socket, :input_values, new_values)}
  end

  @impl true
  def handle_info({:simulator_status_changed, status}, socket) do
    {:noreply, assign(socket, :nav_simulator_status, status)}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    socket = assign(socket, :nav_devices, devices)

    # Update active port if configuration is applied to a device
    config_id = socket.assigns.device.config_id
    active_port = find_active_port_in_list(devices, config_id)

    socket =
      if active_port != socket.assigns.active_port do
        if active_port do
          Hardware.subscribe_input_values(active_port)
          assign(socket, :active_port, active_port)
        else
          socket
          |> assign(:active_port, nil)
          |> assign(:input_values, %{})
        end
      else
        socket
      end

    {:noreply, socket}
  end

  defp find_active_port_in_list(devices, config_id) do
    devices
    |> Enum.find(&(&1.device_config_id == config_id && &1.status == :connected))
    |> then(fn
      nil -> nil
      device -> device.port
    end)
  end

  # Render

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
        firmware_update={@nav_firmware_update}
        firmware_checking={@nav_firmware_checking}
        dropdown_open={@nav_dropdown_open}
        scanning={@nav_scanning}
        current_path={@nav_current_path}
      />

      <.breadcrumb items={[
        %{label: "Configurations", path: ~p"/"},
        %{label: @device.name || "New Configuration"}
      ]} />

      <main class="flex-1 p-4 sm:p-8">
        <div class="max-w-2xl mx-auto">
          <.device_header
            device={@device}
            device_form={@device_form}
            active_port={@active_port}
            new_mode={@new_mode}
          />

          <div class="bg-base-200/50 rounded-xl p-6 mt-6">
            <.status_section
              active_port={@active_port}
              new_mode={@new_mode}
              connected_devices={@connected_devices}
              applying={@applying}
              inputs={@inputs}
            />

            <.inputs_section
              inputs={@inputs}
              input_values={@input_values}
              active_port={@active_port}
            />

            <.outputs_section />
          </div>

          <.danger_zone :if={not @new_mode} active={@active_port != nil} />
        </div>
      </main>

      <.add_input_modal :if={@modal_open} form={@form} />

      <.apply_modal
        :if={@show_apply_modal}
        device={@device}
        connected_devices={@connected_devices}
      />

      <.delete_modal
        :if={@show_delete_modal}
        device={@device}
        active={@active_port != nil}
      />

      <.live_component
        :if={@calibrating_input}
        module={TswIoWeb.CalibrationWizard}
        id="calibration-wizard"
        input={@calibrating_input}
        port={@active_port}
        session_state={@calibration_session_state}
      />
    </div>
    """
  end

  # Components

  attr :device, :map, required: true
  attr :device_form, :map, required: true
  attr :active_port, :string, default: nil
  attr :new_mode, :boolean, required: true

  defp device_header(assigns) do
    ~H"""
    <header>
      <.form for={@device_form} phx-change="validate_device" phx-submit="save_device">
        <.input
          field={@device_form[:name]}
          type="text"
          class="text-2xl font-semibold bg-transparent border border-base-300/0 hover:border-base-300/50 hover:bg-base-200/20 p-2 -ml-2 focus:ring-2 focus:ring-primary focus:border-primary w-full transition-all rounded-md"
          placeholder="Configuration Name"
        />
        <.input
          field={@device_form[:description]}
          type="textarea"
          class="text-sm text-base-content/70 bg-transparent border border-base-300/0 hover:border-base-300/50 hover:bg-base-200/20 p-2 -ml-2 focus:ring-2 focus:ring-primary focus:border-primary w-full resize-none mt-1 transition-all rounded-md"
          placeholder="Add a description..."
          rows="2"
        />
        <div class="flex items-center gap-3 mt-2">
          <span class="text-xs text-base-content/50 font-mono">ID: {@device.config_id}</span>
          <span :if={@active_port} class="badge badge-success badge-sm gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-success-content animate-pulse" />
            Active on {@active_port}
          </span>
          <button type="submit" class="btn btn-ghost btn-xs ml-auto">
            <.icon name="hero-check" class="w-4 h-4" /> Save
          </button>
        </div>
      </.form>
    </header>
    """
  end

  attr :active_port, :string, default: nil
  attr :new_mode, :boolean, required: true
  attr :connected_devices, :list, required: true
  attr :applying, :boolean, required: true
  attr :inputs, :list, required: true

  defp status_section(assigns) do
    can_apply = length(assigns.inputs) > 0 and not Enum.empty?(assigns.connected_devices)
    assigns = assign(assigns, :can_apply, can_apply)

    ~H"""
    <div class="mb-6 p-4 rounded-lg bg-base-100 border border-base-300">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span :if={@active_port} class="w-3 h-3 rounded-full bg-success animate-pulse" />
          <span :if={!@active_port} class="w-3 h-3 rounded-full bg-base-content/20" />
          <div>
            <p :if={@active_port} class="font-medium">Active on {@active_port}</p>
            <p :if={!@active_port && Enum.empty?(@connected_devices)} class="text-base-content/70">
              No devices connected
            </p>
            <p :if={!@active_port && not Enum.empty?(@connected_devices)} class="text-base-content/70">
              Not applied to any device
            </p>
          </div>
        </div>

        <button
          :if={@can_apply}
          type="button"
          phx-click="show_apply_modal"
          disabled={@applying}
          class="btn btn-primary btn-sm"
        >
          <.icon :if={@applying} name="hero-arrow-path" class="w-4 h-4 animate-spin" />
          <.icon :if={!@applying} name="hero-play" class="w-4 h-4" />
          {if @applying, do: "Applying...", else: "Apply to Device"}
        </button>
      </div>
    </div>
    """
  end

  attr :inputs, :list, required: true
  attr :input_values, :map, required: true
  attr :active_port, :string, default: nil

  defp inputs_section(assigns) do
    ~H"""
    <div class="mb-6">
      <h3 class="text-base font-semibold mb-4">Inputs</h3>

      <.empty_inputs_state :if={Enum.empty?(@inputs)} />

      <.inputs_table
        :if={length(@inputs) > 0}
        inputs={@inputs}
        input_values={@input_values}
        active_port={@active_port}
      />

      <button phx-click="open_add_input_modal" class="btn btn-outline btn-sm mt-4">
        <.icon name="hero-plus" class="w-4 h-4" /> Add Input
      </button>
    </div>
    """
  end

  defp empty_inputs_state(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg p-8 text-center">
      <.icon name="hero-plus-circle" class="w-10 h-10 mx-auto text-base-content/30" />
      <p class="mt-2 text-sm text-base-content/70">No inputs configured</p>
      <p class="text-xs text-base-content/50">Add your first input to get started</p>
    </div>
    """
  end

  attr :inputs, :list, required: true
  attr :input_values, :map, required: true
  attr :active_port, :string, default: nil

  defp inputs_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm bg-base-100 rounded-lg">
        <thead>
          <tr class="bg-base-200">
            <th class="text-center">Pin</th>
            <th>Type</th>
            <th>Sensitivity</th>
            <th>Raw</th>
            <th>Calibrated</th>
            <th class="w-24"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={input <- @inputs} class="hover:bg-base-200/50">
            <td class="text-center font-mono">{input.pin}</td>
            <td>
              <span class="badge badge-info badge-sm capitalize">{input.input_type}</span>
            </td>
            <td class="font-mono text-sm">{input.sensitivity}</td>
            <td>
              <.raw_value value={Map.get(@input_values, input.pin)} active={@active_port != nil} />
            </td>
            <td>
              <.calibrated_value
                raw_value={Map.get(@input_values, input.pin)}
                calibration={input.calibration}
                active={@active_port != nil}
              />
            </td>
            <td class="flex gap-1">
              <button
                :if={@active_port != nil}
                phx-click="start_calibration"
                phx-value-id={input.id}
                class="btn btn-ghost btn-xs text-primary hover:bg-primary/10"
              >
                <.icon name="hero-adjustments-horizontal" class="w-4 h-4" /> Calibrate
              </button>
              <button
                phx-click="delete_input"
                phx-value-id={input.id}
                class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                aria-label="Delete input"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :value, :integer, default: nil
  attr :active, :boolean, required: true

  defp raw_value(assigns) do
    ~H"""
    <span :if={!@active} class="text-base-content/50 italic text-sm">
      <.icon name="hero-lock-closed" class="w-3 h-3 inline mr-1" /> N/A
    </span>
    <span :if={@active && is_nil(@value)} class="text-base-content/50">
      &mdash;
    </span>
    <span :if={@active && !is_nil(@value)} class="font-mono">
      {@value}
    </span>
    """
  end

  attr :raw_value, :integer, default: nil
  attr :calibration, :map, default: nil
  attr :active, :boolean, required: true

  defp calibrated_value(assigns) do
    calibration = loaded_calibration(assigns.calibration)

    calibrated =
      if assigns.raw_value && calibration do
        Hardware.normalize_value(assigns.raw_value, calibration)
      else
        nil
      end

    assigns =
      assigns
      |> assign(:calibration, calibration)
      |> assign(:calibrated, calibrated)

    ~H"""
    <span :if={!@active} class="text-base-content/50 italic text-sm">N/A</span>
    <span :if={@active && is_nil(@calibration)} class="text-base-content/50 text-sm">
      Not calibrated
    </span>
    <span :if={@active && @calibration && is_nil(@raw_value)} class="text-base-content/50">
      &mdash;
    </span>
    <span :if={@active && @calibration && !is_nil(@calibrated)} class="font-mono">
      {@calibrated}
    </span>
    """
  end

  defp loaded_calibration(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_calibration(nil), do: nil
  defp loaded_calibration(calibration), do: calibration

  defp outputs_section(assigns) do
    ~H"""
    <div class="mb-6">
      <h3 class="text-base font-semibold mb-4">Outputs</h3>
      <div class="bg-base-100 rounded-lg p-6 text-center border border-base-300 border-dashed">
        <p class="text-sm text-base-content/50">Coming soon</p>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  defp add_input_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/50" phx-click="close_add_input_modal" />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-md mx-4 p-6">
        <h2 class="text-xl font-semibold mb-4">Add Input</h2>

        <.form for={@form} phx-change="validate_input" phx-submit="add_input">
          <div class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text">Pin Number</span>
              </label>
              <.input
                field={@form[:pin]}
                type="number"
                placeholder="Enter pin number (1-254)"
                min="1"
                max="254"
                class="input input-bordered w-full"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text">Input Type</span>
              </label>
              <.input
                field={@form[:input_type]}
                type="select"
                options={[{"Analog", :analog}]}
                class="select select-bordered w-full"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text">Sensitivity (1-10)</span>
              </label>
              <.input
                field={@form[:sensitivity]}
                type="number"
                min="1"
                max="10"
                class="input input-bordered w-full"
              />
            </div>
          </div>

          <div class="flex justify-end gap-2 mt-6">
            <button type="button" phx-click="close_add_input_modal" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              Add Input
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :device, :map, required: true
  attr :connected_devices, :list, required: true

  defp apply_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="fixed inset-0 bg-black/50" phx-click="close_apply_modal" />
      <div class="relative bg-base-100 rounded-xl shadow-xl max-w-md w-full p-6">
        <h3 class="text-lg font-semibold mb-4">Apply Configuration</h3>
        <p class="text-sm text-base-content/70 mb-6">
          Select a device to apply "<span class="font-medium">{@device.name}</span>" to:
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

  attr :active, :boolean, required: true

  defp danger_zone(assigns) do
    ~H"""
    <div class="mt-12 pt-8 border-t border-base-300">
      <h3 class="text-sm font-semibold text-error mb-4">Danger Zone</h3>
      <div class="p-4 rounded-lg border border-error/30 bg-error/5">
        <div class="flex items-center justify-between gap-4">
          <div>
            <p class="font-medium text-sm">Delete Configuration</p>
            <p class="text-xs text-base-content/70 mt-1">
              Permanently remove this configuration and all associated data
            </p>
          </div>
          <button
            type="button"
            phx-click="show_delete_modal"
            disabled={@active}
            class="btn btn-error btn-sm"
          >
            <.icon name="hero-trash" class="w-4 h-4" /> Delete
          </button>
        </div>
        <p :if={@active} class="text-xs text-warning mt-3">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline" />
          Cannot delete while configuration is active on a device
        </p>
      </div>
    </div>
    """
  end

  attr :device, :map, required: true
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
          Are you sure you want to delete "<span class="font-medium">{@device.name}</span>"?
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
end
