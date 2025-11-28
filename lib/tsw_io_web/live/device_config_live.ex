defmodule TswIoWeb.DeviceConfigLive do
  use TswIoWeb, :live_view

  alias TswIo.Hardware
  alias TswIo.Hardware.Input
  alias TswIo.Hardware.Calibration.Session
  alias TswIo.Serial.Connection

  @impl true
  def mount(%{"port" => encoded_port}, _session, socket) do
    port = URI.decode(encoded_port)

    if connected?(socket) do
      Hardware.subscribe_configuration()
      Hardware.subscribe_input_values(port)
      Connection.subscribe()
    end

    case find_connection(port) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Device not found")
         |> redirect(to: ~p"/")}

      connection ->
        {device, draft_mode} = load_or_create_device(connection)
        {:ok, inputs} = Hardware.list_inputs(device.id)
        input_values = Hardware.get_input_values(port)

        {:ok,
         socket
         |> assign(:port, port)
         |> assign(:device, device)
         |> assign(:connection, connection)
         |> assign(:inputs, inputs)
         |> assign(:input_values, input_values)
         |> assign(:draft_mode, draft_mode)
         |> assign(:modal_open, false)
         |> assign(
           :form,
           to_form(Input.changeset(%Input{}, %{input_type: :analog, sensitivity: 5}))
         )
         |> assign(:applying, false)
         |> assign(:calibrating_input, nil)
         |> assign(:calibration_session_state, nil)}
    end
  end

  defp find_connection(port) do
    Connection.list_devices()
    |> Enum.find(&(&1.port == port && &1.status == :connected))
  end

  defp load_or_create_device(connection) do
    case connection.device_config_id do
      nil ->
        # No config on device, create a new device in draft mode
        {:ok, device} = Hardware.create_device(%{name: "Device #{connection.port}"})
        {device, true}

      config_id ->
        case Hardware.get_device_by_config_id(config_id) do
          {:ok, device} ->
            {device, false}

          {:error, :not_found} ->
            # Device has config_id but we don't have it in DB (device was configured elsewhere)
            {:ok, device} = Hardware.create_device(%{name: "Device #{connection.port}"})
            {device, true}
        end
    end
  end

  # Event Handlers

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

  @impl true
  def handle_event("apply_configuration", _params, socket) do
    socket = assign(socket, :applying, true)

    case Hardware.apply_configuration(socket.assigns.port, socket.assigns.device.id) do
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
         |> put_flash(:error, "Failed to start configuration: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_calibration", %{"id" => id}, socket) do
    input = Enum.find(socket.assigns.inputs, &(&1.id == String.to_integer(id)))

    if input && !socket.assigns.draft_mode do
      Session.subscribe(input.id)
      {:noreply, assign(socket, :calibrating_input, input)}
    else
      {:noreply, socket}
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
    # Forward session state to the CalibrationWizard component
    {:noreply, assign(socket, :calibration_session_state, state)}
  end

  @impl true
  def handle_info({:configuration_applied, _port, device, _config_id}, socket) do
    {:noreply,
     socket
     |> assign(:device, device)
     |> assign(:draft_mode, false)
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
  def handle_info({:devices_updated, devices}, socket) do
    connection = Enum.find(devices, &(&1.port == socket.assigns.port && &1.status == :connected))

    if connection do
      {:noreply, assign(socket, :connection, connection)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Device disconnected")
       |> redirect(to: ~p"/")}
    end
  end

  # Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.nav_header port={@port} device_version={@connection.device_version} />

      <main class="flex-1 p-8">
        <div class="max-w-2xl mx-auto">
          <.page_header port={@port} device_version={@connection.device_version} />

          <div class="bg-base-200/50 rounded-xl p-6 mt-6">
            <div class="flex items-center justify-between mb-6">
              <h2 class="text-lg font-semibold">Configuration</h2>
              <.status_badge draft_mode={@draft_mode} />
            </div>

            <.inputs_section
              inputs={@inputs}
              input_values={@input_values}
              draft_mode={@draft_mode}
            />

            <.outputs_section />

            <.apply_button
              :if={length(@inputs) > 0 && @draft_mode}
              applying={@applying}
            />
          </div>
        </div>
      </main>

      <.add_input_modal :if={@modal_open} form={@form} />

      <.live_component
        :if={@calibrating_input}
        module={TswIoWeb.CalibrationWizard}
        id="calibration-wizard"
        input={@calibrating_input}
        port={@port}
        session_state={@calibration_session_state}
      />
    </div>
    """
  end

  # Components

  attr :port, :string, required: true
  attr :device_version, :string, default: nil

  defp nav_header(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-300 px-4 sticky top-0 z-50">
      <div class="flex-1">
        <a href="/" class="flex items-center gap-2 text-base-content/70 hover:text-base-content">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
          <span class="text-sm">Back to Devices</span>
        </a>
      </div>
      <div class="flex-none">
        <span class="text-sm text-base-content/70">TWS IO</span>
      </div>
    </header>
    """
  end

  attr :port, :string, required: true
  attr :device_version, :string, default: nil

  defp page_header(assigns) do
    ~H"""
    <header>
      <h1 class="text-2xl font-semibold">Device Configuration</h1>
      <p class="text-sm text-base-content/70 mt-1">
        {@port}
        <span :if={@device_version}> &middot; v{@device_version}</span>
      </p>
    </header>
    """
  end

  attr :draft_mode, :boolean, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={@draft_mode} class="badge badge-warning badge-sm gap-1">
      <.icon name="hero-pencil-square" class="w-3 h-3" /> Draft
    </span>
    <span :if={!@draft_mode} class="badge badge-success badge-sm gap-1">
      <.icon name="hero-check-circle" class="w-3 h-3" /> Active
    </span>
    """
  end

  attr :inputs, :list, required: true
  attr :input_values, :map, required: true
  attr :draft_mode, :boolean, required: true

  defp inputs_section(assigns) do
    ~H"""
    <div class="mb-6">
      <h3 class="text-base font-semibold mb-4">Inputs</h3>

      <.empty_inputs_state :if={Enum.empty?(@inputs)} />

      <.inputs_table
        :if={length(@inputs) > 0}
        inputs={@inputs}
        input_values={@input_values}
        draft_mode={@draft_mode}
      />

      <button
        phx-click="open_add_input_modal"
        class="btn btn-outline btn-sm mt-4"
      >
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
  attr :draft_mode, :boolean, required: true

  defp inputs_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm bg-base-100 rounded-lg">
        <thead>
          <tr class="bg-base-200">
            <th class="text-center">Pin</th>
            <th>Type</th>
            <th>Sensitivity</th>
            <th>Value</th>
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
              <.input_value
                value={Map.get(@input_values, input.pin)}
                draft_mode={@draft_mode}
              />
            </td>
            <td class="flex gap-1">
              <button
                :if={!@draft_mode}
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
  attr :draft_mode, :boolean, required: true

  defp input_value(assigns) do
    ~H"""
    <span :if={@draft_mode} class="text-base-content/50 italic text-sm">
      <.icon name="hero-lock-closed" class="w-3 h-3 inline mr-1" /> N/A
    </span>
    <span :if={!@draft_mode && is_nil(@value)} class="text-base-content/50">
      &mdash;
    </span>
    <span :if={!@draft_mode && !is_nil(@value)} class="font-mono">
      {@value}
    </span>
    """
  end

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

  attr :applying, :boolean, required: true

  defp apply_button(assigns) do
    ~H"""
    <div class="pt-4 border-t border-base-300">
      <button
        phx-click="apply_configuration"
        disabled={@applying}
        class="btn btn-primary w-full"
      >
        <.icon :if={@applying} name="hero-arrow-path" class="w-4 h-4 animate-spin" />
        <.icon :if={!@applying} name="hero-check" class="w-4 h-4" />
        {if @applying, do: "Applying...", else: "Apply Configuration"}
      </button>
    </div>
    """
  end

  attr :form, :map, required: true

  defp add_input_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div
        class="absolute inset-0 bg-black/50"
        phx-click="close_add_input_modal"
      />
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
            <button
              type="button"
              phx-click="close_add_input_modal"
              class="btn btn-ghost"
            >
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
end
