defmodule TswIoWeb.TrainEditLive do
  @moduledoc """
  LiveView for editing a train configuration.

  Supports both creating new trains and editing existing ones.
  Allows managing train elements (levers, etc.) and their configurations.
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents
  import TswIoWeb.SharedComponents

  alias TswIo.Hardware
  alias TswIo.Train, as: TrainContext
  alias TswIo.Train.{Train, Element, LeverConfig, LeverInputBinding, Notch}
  alias TswIo.Train.LeverController
  alias TswIo.Serial.Connection

  @impl true
  def mount(%{"train_id" => "new"} = params, _session, socket) do
    mount_new(socket, params)
  end

  @impl true
  def mount(%{"train_id" => train_id_str}, _session, socket) do
    case Integer.parse(train_id_str) do
      {train_id, ""} ->
        mount_existing(socket, train_id)

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid train ID")
         |> redirect(to: ~p"/trains")}
    end
  end

  defp mount_new(socket, params) do
    if connected?(socket) do
      TrainContext.subscribe()
    end

    # Check for pre-filled identifier from URL query params
    identifier = params["identifier"] || ""

    train = %Train{name: "", description: nil, identifier: identifier}
    changeset = Train.changeset(train, %{})

    {:ok,
     socket
     |> assign(:train, train)
     |> assign(:train_form, to_form(changeset))
     |> assign(:elements, [])
     |> assign(:new_mode, true)
     |> assign(:active_train, TrainContext.get_active_train())
     |> assign(:modal_open, false)
     |> assign(:element_form, to_form(Element.changeset(%Element{}, %{type: :lever})))
     |> assign(:show_delete_modal, false)
     |> assign(:configuring_element, nil)
     |> assign(:lever_config_form, nil)
     |> assign(:mapping_notches_element, nil)
     |> assign(:notch_forms, [])
     |> assign(:auto_detecting, false)
     |> assign(:calibration_progress, nil)
     |> assign(:show_api_explorer, false)
     |> assign(:api_explorer_field, nil)
     |> assign(:binding_element, nil)
     |> assign(:available_inputs, [])
     |> assign(:notch_mapping_wizard_element, nil)
     |> assign(:notch_mapping_state, nil)}
  end

  defp mount_existing(socket, train_id) do
    case TrainContext.get_train(train_id, preload: [elements: [lever_config: [:notches, input_binding: [input: :device]]]]) do
      {:ok, train} ->
        if connected?(socket) do
          TrainContext.subscribe()
        end

        changeset = Train.changeset(train, %{})

        {:ok,
         socket
         |> assign(:train, train)
         |> assign(:train_form, to_form(changeset))
         |> assign(:elements, train.elements)
         |> assign(:new_mode, false)
         |> assign(:active_train, TrainContext.get_active_train())
         |> assign(:modal_open, false)
         |> assign(:element_form, to_form(Element.changeset(%Element{}, %{type: :lever})))
         |> assign(:show_delete_modal, false)
         |> assign(:configuring_element, nil)
         |> assign(:lever_config_form, nil)
         |> assign(:mapping_notches_element, nil)
         |> assign(:notch_forms, [])
         |> assign(:auto_detecting, false)
         |> assign(:calibration_progress, nil)
         |> assign(:show_api_explorer, false)
         |> assign(:api_explorer_field, nil)
         |> assign(:binding_element, nil)
         |> assign(:available_inputs, [])
         |> assign(:notch_mapping_wizard_element, nil)
         |> assign(:notch_mapping_state, nil)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Train not found")
         |> redirect(to: ~p"/trains")}
    end
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

  # Train name/description editing
  @impl true
  def handle_event("validate_train", %{"train" => params}, socket) do
    changeset =
      socket.assigns.train
      |> Train.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :train_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_train", %{"train" => params}, socket) do
    save_train(socket, params)
  end

  # Element management
  @impl true
  def handle_event("open_add_element_modal", _params, socket) do
    {:noreply, assign(socket, :modal_open, true)}
  end

  @impl true
  def handle_event("close_add_element_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal_open, false)
     |> assign(:element_form, to_form(Element.changeset(%Element{}, %{type: :lever})))}
  end

  @impl true
  def handle_event("validate_element", %{"element" => params}, socket) do
    changeset =
      %Element{}
      |> Element.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :element_form, to_form(changeset))}
  end

  @impl true
  def handle_event("add_element", %{"element" => params}, socket) do
    case TrainContext.create_element(socket.assigns.train.id, params) do
      {:ok, _element} ->
        {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)

        {:noreply,
         socket
         |> assign(:elements, elements)
         |> assign(:modal_open, false)
         |> assign(:element_form, to_form(Element.changeset(%Element{}, %{type: :lever})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :element_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_element", %{"id" => id}, socket) do
    case TrainContext.get_element(String.to_integer(id)) do
      {:ok, element} ->
        case TrainContext.delete_element(element) do
          {:ok, _} ->
            {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)
            {:noreply, assign(socket, :elements, elements)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete element")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Element not found")}
    end
  end

  # Lever configuration
  @impl true
  def handle_event("configure_lever", %{"id" => id}, socket) do
    element_id = String.to_integer(id)

    case TrainContext.get_element(element_id, preload: [lever_config: :notches]) do
      {:ok, element} ->
        lever_config = element.lever_config || %LeverConfig{element_id: element_id}
        changeset = LeverConfig.changeset(lever_config, %{})

        {:noreply,
         socket
         |> assign(:configuring_element, element)
         |> assign(:lever_config_form, to_form(changeset))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Element not found")}
    end
  end

  @impl true
  def handle_event("close_lever_config_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:configuring_element, nil)
     |> assign(:lever_config_form, nil)}
  end

  @impl true
  def handle_event("validate_lever_config", %{"lever_config" => params}, socket) do
    lever_config = socket.assigns.configuring_element.lever_config || %LeverConfig{}

    changeset =
      lever_config
      |> LeverConfig.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :lever_config_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_lever_config", %{"lever_config" => params}, socket) do
    element = socket.assigns.configuring_element

    result =
      if element.lever_config do
        TrainContext.update_lever_config(element.lever_config, params)
      else
        TrainContext.create_lever_config(element.id, params)
      end

    case result do
      {:ok, _config} ->
        {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)

        {:noreply,
         socket
         |> assign(:elements, elements)
         |> assign(:configuring_element, nil)
         |> assign(:lever_config_form, nil)
         |> put_flash(:info, "Lever configuration saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, :lever_config_form, to_form(changeset))}
    end
  end

  # Input binding
  @impl true
  def handle_event("open_input_binding", %{"id" => id}, socket) do
    element_id = String.to_integer(id)

    case TrainContext.get_element(element_id, preload: [lever_config: [:notches, :input_binding]]) do
      {:ok, element} ->
        if element.lever_config do
          available_inputs = Hardware.list_all_inputs()

          {:noreply,
           socket
           |> assign(:binding_element, element)
           |> assign(:available_inputs, available_inputs)}
        else
          {:noreply, put_flash(socket, :error, "Please configure lever endpoints first")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Element not found")}
    end
  end

  @impl true
  def handle_event("close_input_binding", _params, socket) do
    {:noreply,
     socket
     |> assign(:binding_element, nil)
     |> assign(:available_inputs, [])
     |> assign(:notch_mapping_wizard_element, nil)
     |> assign(:notch_mapping_state, nil)}
  end

  @impl true
  def handle_event("bind_input", %{"input_id" => input_id_str}, socket) do
    input_id = String.to_integer(input_id_str)
    element = socket.assigns.binding_element

    case TrainContext.bind_input(element.lever_config.id, input_id) do
      {:ok, _binding} ->
        {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)
        LeverController.reload_bindings()

        {:noreply,
         socket
         |> assign(:elements, elements)
         |> assign(:binding_element, nil)
         |> assign(:available_inputs, [])
         |> put_flash(:info, "Input bound successfully")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to bind input: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_event("unbind_input", _params, socket) do
    element = socket.assigns.binding_element

    case TrainContext.unbind_input(element.lever_config.id) do
      :ok ->
        {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)
        LeverController.reload_bindings()

        {:noreply,
         socket
         |> assign(:elements, elements)
         |> assign(:binding_element, nil)
         |> assign(:available_inputs, [])
         |> put_flash(:info, "Input unbound")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No binding found")}
    end
  end

  # Guided notch mapping wizard
  @impl true
  def handle_event("open_guided_notch_mapping", %{"id" => id}, socket) do
    element_id = String.to_integer(id)

    case TrainContext.get_element(element_id,
           preload: [
             lever_config: [:notches, input_binding: [input: [device: [], calibration: []]]]
           ]
         ) do
      {:ok, element} ->
        cond do
          is_nil(element.lever_config) ->
            {:noreply, put_flash(socket, :error, "Please configure lever endpoints first")}

          is_nil(get_input_binding(element.lever_config)) ->
            {:noreply, put_flash(socket, :error, "Please bind an input first")}

          is_nil(get_bound_input_calibration(element)) ->
            {:noreply, put_flash(socket, :error, "The bound input is not calibrated")}

          Enum.empty?(element.lever_config.notches) ->
            {:noreply, put_flash(socket, :error, "Please add notches first (use Map Notches)")}

          true ->
            # Subscribe to notch mapping events
            TrainContext.subscribe_notch_mapping(element.lever_config.id)

            {:noreply,
             socket
             |> assign(:notch_mapping_wizard_element, element)
             |> assign(:notch_mapping_state, nil)}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Element not found")}
    end
  end

  @impl true
  def handle_event("close_guided_notch_mapping", _params, socket) do
    if socket.assigns.notch_mapping_wizard_element do
      lever_config_id = socket.assigns.notch_mapping_wizard_element.lever_config.id
      TrainContext.stop_notch_mapping(lever_config_id)
    end

    {:noreply,
     socket
     |> assign(:notch_mapping_wizard_element, nil)
     |> assign(:notch_mapping_state, nil)}
  end

  @impl true
  def handle_event("auto_distribute_ranges", _params, socket) do
    element = socket.assigns.mapping_notches_element

    case TrainContext.auto_distribute_input_ranges(element.lever_config.id) do
      {:ok, updated_config} ->
        notch_forms = build_notch_forms(updated_config.notches)
        LeverController.reload_bindings()

        {:noreply,
         socket
         |> assign(:notch_forms, notch_forms)
         |> assign(:mapping_notches_element, %{element | lever_config: updated_config})
         |> put_flash(:info, "Input ranges distributed evenly")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to distribute ranges: #{inspect(reason)}")}
    end
  end

  # Notch mapping
  @impl true
  def handle_event("open_notch_mapping", %{"id" => id}, socket) do
    element_id = String.to_integer(id)

    case TrainContext.get_element(element_id, preload: [lever_config: :notches]) do
      {:ok, element} ->
        if element.lever_config do
          notch_forms = build_notch_forms(element.lever_config.notches)

          {:noreply,
           socket
           |> assign(:mapping_notches_element, element)
           |> assign(:notch_forms, notch_forms)
           |> assign(:auto_detecting, false)}
        else
          {:noreply, put_flash(socket, :error, "Please configure lever endpoints first")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Element not found")}
    end
  end

  @impl true
  def handle_event("close_notch_mapping", _params, socket) do
    {:noreply,
     socket
     |> assign(:mapping_notches_element, nil)
     |> assign(:notch_forms, [])
     |> assign(:auto_detecting, false)}
  end

  @impl true
  def handle_event("auto_detect_notches", _params, socket) do
    element = socket.assigns.mapping_notches_element
    simulator_status = socket.assigns.nav_simulator_status

    cond do
      simulator_status.status != :connected ->
        {:noreply, put_flash(socket, :error, "Simulator not connected")}

      simulator_status.client == nil ->
        {:noreply, put_flash(socket, :error, "No simulator client available")}

      element.lever_config.notch_count_endpoint == nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Notch count endpoint not configured. Configure notch endpoints first."
         )}

      true ->
        # Subscribe to calibration events
        TrainContext.subscribe_calibration(element.lever_config.id)

        # Start the calibration session
        case TrainContext.start_calibration(simulator_status.client, element.lever_config) do
          {:ok, _pid} ->
            {:noreply,
             socket
             |> assign(:auto_detecting, true)
             |> assign(:calibration_progress, 0.0)}

          {:error, :already_running} ->
            {:noreply, put_flash(socket, :error, "Calibration already in progress")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start calibration: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("add_notch", _params, socket) do
    new_notch_form =
      Notch.changeset(%Notch{}, %{type: :gate, value: 0.0})
      |> to_form()

    notch_forms = socket.assigns.notch_forms ++ [new_notch_form]
    {:noreply, assign(socket, :notch_forms, notch_forms)}
  end

  @impl true
  def handle_event("remove_notch", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    notch_forms = List.delete_at(socket.assigns.notch_forms, index)
    {:noreply, assign(socket, :notch_forms, notch_forms)}
  end

  @impl true
  def handle_event("validate_notch", %{"index" => index_str, "notch" => params}, socket) do
    index = String.to_integer(index_str)
    notch_forms = socket.assigns.notch_forms

    updated_form =
      %Notch{}
      |> Notch.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form()

    notch_forms = List.replace_at(notch_forms, index, updated_form)
    {:noreply, assign(socket, :notch_forms, notch_forms)}
  end

  @impl true
  def handle_event("save_notches", _params, socket) do
    element = socket.assigns.mapping_notches_element
    notch_forms = socket.assigns.notch_forms

    # Extract params from all forms
    notch_params =
      Enum.map(notch_forms, fn form ->
        form.params
      end)

    case TrainContext.save_notches(element.lever_config, notch_params) do
      {:ok, _updated_config} ->
        {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)

        {:noreply,
         socket
         |> assign(:elements, elements)
         |> assign(:mapping_notches_element, nil)
         |> assign(:notch_forms, [])
         |> put_flash(:info, "Notches saved successfully")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save notches: #{inspect(reason)}")}
    end
  end

  # Delete train
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
    train = socket.assigns.train

    case TrainContext.delete_train(train) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Train \"#{train.name}\" deleted")
         |> redirect(to: ~p"/trains")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete: #{inspect(reason)}")
         |> assign(:show_delete_modal, false)}
    end
  end

  # API Explorer events
  @impl true
  def handle_event("open_api_explorer", %{"field" => field}, socket) do
    simulator_status = socket.assigns.nav_simulator_status

    if simulator_status.status == :connected and simulator_status.client != nil do
      {:noreply,
       socket
       |> assign(:show_api_explorer, true)
       |> assign(:api_explorer_field, String.to_existing_atom(field))}
    else
      {:noreply, put_flash(socket, :error, "Simulator not connected")}
    end
  end

  # PubSub events
  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, :nav_devices, devices)}
  end

  @impl true
  def handle_info({:simulator_status_changed, status}, socket) do
    {:noreply, assign(socket, :nav_simulator_status, status)}
  end

  @impl true
  def handle_info({:train_detected, %{train: train}}, socket) do
    {:noreply, assign(socket, :active_train, train)}
  end

  @impl true
  def handle_info({:train_changed, train}, socket) do
    {:noreply, assign(socket, :active_train, train)}
  end

  @impl true
  def handle_info({:detection_error, _reason}, socket) do
    {:noreply, socket}
  end

  # Calibration events
  @impl true
  def handle_info({:calibration_progress, progress_state}, socket) do
    {:noreply, assign(socket, :calibration_progress, progress_state.progress)}
  end

  @impl true
  def handle_info({:calibration_result, {:ok, updated_config}}, socket) do
    # Reload the element to get fresh notches
    element = socket.assigns.mapping_notches_element
    config_with_notches = TswIo.Repo.preload(updated_config, :notches)

    notch_forms = build_notch_forms(config_with_notches.notches)

    {:noreply,
     socket
     |> assign(:notch_forms, notch_forms)
     |> assign(:auto_detecting, false)
     |> assign(:calibration_progress, nil)
     |> assign(:mapping_notches_element, %{element | lever_config: config_with_notches})
     |> put_flash(
       :info,
       "Calibration complete! Detected #{length(config_with_notches.notches)} notches"
     )}
  end

  @impl true
  def handle_info({:calibration_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:auto_detecting, false)
     |> assign(:calibration_progress, nil)
     |> put_flash(:error, "Calibration failed: #{inspect(reason)}")}
  end

  # Notch mapping wizard events
  @impl true
  def handle_info({:session_started, state}, socket) do
    {:noreply, assign(socket, :notch_mapping_state, state)}
  end

  @impl true
  def handle_info({:step_changed, state}, socket) do
    {:noreply, assign(socket, :notch_mapping_state, state)}
  end

  @impl true
  def handle_info({:sample_updated, state}, socket) do
    {:noreply, assign(socket, :notch_mapping_state, state)}
  end

  @impl true
  def handle_info({:capture_started, state}, socket) do
    {:noreply, assign(socket, :notch_mapping_state, state)}
  end

  @impl true
  def handle_info({:capture_stopped, state}, socket) do
    {:noreply, assign(socket, :notch_mapping_state, state)}
  end

  @impl true
  def handle_info({:mapping_result, {:ok, _updated_config}}, socket) do
    {:ok, elements} = TrainContext.list_elements(socket.assigns.train.id)
    LeverController.reload_bindings()

    # The wizard will show the success state, we just need to update the elements
    {:noreply,
     socket
     |> assign(:elements, elements)}
  end

  @impl true
  def handle_info({:mapping_result, {:error, _reason}}, socket) do
    # Error is shown in the wizard, no action needed here
    {:noreply, socket}
  end

  @impl true
  def handle_info(:notch_mapping_cancelled, socket) do
    {:noreply,
     socket
     |> assign(:notch_mapping_wizard_element, nil)
     |> assign(:notch_mapping_state, nil)}
  end

  # API Explorer component events
  @impl true
  def handle_info({:api_explorer_select, field, path}, socket) do
    # Update the lever config form with the selected path
    current_form = socket.assigns.lever_config_form
    current_params = current_form.params || %{}
    updated_params = Map.put(current_params, Atom.to_string(field), path)

    lever_config = socket.assigns.configuring_element.lever_config || %LeverConfig{}
    changeset = LeverConfig.changeset(lever_config, updated_params)

    {:noreply,
     socket
     |> assign(:lever_config_form, to_form(changeset))
     |> assign(:show_api_explorer, false)
     |> assign(:api_explorer_field, nil)}
  end

  @impl true
  def handle_info({:api_explorer_close}, socket) do
    {:noreply,
     socket
     |> assign(:show_api_explorer, false)
     |> assign(:api_explorer_field, nil)}
  end

  # Private functions

  defp build_notch_forms(notches) when is_list(notches) do
    Enum.map(notches, fn notch ->
      Notch.changeset(notch, %{})
      |> to_form()
    end)
  end

  defp save_train(%{assigns: %{new_mode: true}} = socket, params) do
    case TrainContext.create_train(params) do
      {:ok, train} ->
        {:noreply,
         socket
         |> put_flash(:info, "Train created")
         |> redirect(to: ~p"/trains/#{train.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :train_form, to_form(changeset))}
    end
  end

  defp save_train(socket, params) do
    case TrainContext.update_train(socket.assigns.train, params) do
      {:ok, train} ->
        changeset = Train.changeset(train, %{})

        {:noreply,
         socket
         |> assign(:train, train)
         |> assign(:train_form, to_form(changeset))
         |> put_flash(:info, "Train saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, :train_form, to_form(changeset))}
    end
  end

  # Render

  @impl true
  def render(assigns) do
    is_active =
      assigns.active_train != nil and
        assigns.train.id != nil and
        assigns.active_train.id == assigns.train.id

    assigns = assign(assigns, :is_active, is_active)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.nav_header
        devices={@nav_devices}
        simulator_status={@nav_simulator_status}
        dropdown_open={@nav_dropdown_open}
        scanning={@nav_scanning}
        current_path={@nav_current_path}
      />

      <.breadcrumb items={[
        %{label: "Trains", path: ~p"/trains"},
        %{label: @train.name || "New Train"}
      ]} />

      <main class="flex-1 p-4 sm:p-8">
        <div class="max-w-2xl mx-auto">
          <.train_header
            train={@train}
            train_form={@train_form}
            is_active={@is_active}
            new_mode={@new_mode}
          />

          <div :if={not @new_mode} class="bg-base-200/50 rounded-xl p-6 mt-6">
            <.elements_section elements={@elements} is_active={@is_active} />
          </div>

          <.danger_zone
            :if={not @new_mode}
            action_label="Delete Train"
            action_description="Permanently remove this train and all associated elements and calibration data"
            on_action="show_delete_modal"
            disabled={@is_active}
            disabled_reason="Cannot delete while train is currently active"
          />
        </div>
      </main>

      <.add_element_modal :if={@modal_open} form={@element_form} />

      <.confirmation_modal
        :if={@show_delete_modal}
        on_close="close_delete_modal"
        on_confirm="confirm_delete"
        title="Delete Train"
        item_name={@train.name}
        description="This will permanently delete the train configuration and all its elements and calibration data."
        is_active={@is_active}
        active_warning="This train is currently active in the simulator."
      />

      <.lever_config_modal
        :if={@configuring_element}
        element={@configuring_element}
        form={@lever_config_form}
        simulator_connected={@nav_simulator_status.status == :connected}
      />

      <.notch_mapping_modal
        :if={@mapping_notches_element}
        element={@mapping_notches_element}
        notch_forms={@notch_forms}
        auto_detecting={@auto_detecting}
        simulator_connected={@nav_simulator_status.status == :connected}
      />

      <.live_component
        :if={@show_api_explorer}
        module={TswIoWeb.ApiExplorerComponent}
        id="api-explorer"
        field={@api_explorer_field}
        client={@nav_simulator_status.client}
      />

      <.input_binding_modal
        :if={@binding_element}
        element={@binding_element}
        available_inputs={@available_inputs}
      />

      <.live_component
        :if={@notch_mapping_wizard_element}
        module={TswIoWeb.NotchMappingWizard}
        id="notch-mapping-wizard"
        lever_config={@notch_mapping_wizard_element.lever_config}
        element_name={@notch_mapping_wizard_element.name}
        port={get_bound_input_port(@notch_mapping_wizard_element)}
        pin={get_bound_input_pin(@notch_mapping_wizard_element)}
        calibration={get_bound_input_calibration(@notch_mapping_wizard_element)}
        session_state={@notch_mapping_state}
      />
    </div>
    """
  end

  # Components

  attr :train, :map, required: true
  attr :train_form, :map, required: true
  attr :is_active, :boolean, required: true
  attr :new_mode, :boolean, required: true

  defp train_header(assigns) do
    ~H"""
    <header>
      <.form for={@train_form} phx-change="validate_train" phx-submit="save_train">
        <.input
          field={@train_form[:name]}
          type="text"
          class="text-2xl font-semibold bg-transparent border border-base-300/0 hover:border-base-300/50 hover:bg-base-200/20 p-2 -ml-2 focus:ring-2 focus:ring-primary focus:border-primary w-full transition-all rounded-md"
          placeholder="Train Name"
        />
        <.input
          field={@train_form[:description]}
          type="textarea"
          class="text-sm text-base-content/70 bg-transparent border border-base-300/0 hover:border-base-300/50 hover:bg-base-200/20 p-2 -ml-2 focus:ring-2 focus:ring-primary focus:border-primary w-full resize-none mt-1 transition-all rounded-md"
          placeholder="Add a description..."
          rows="2"
        />
        <div class="mt-3">
          <label class="label">
            <span class="label-text text-sm text-base-content/70">Train Identifier</span>
          </label>
          <.input
            field={@train_form[:identifier]}
            type="text"
            class="input input-bordered w-full font-mono"
            placeholder="e.g., BR_Class_66"
          />
          <p class="text-xs text-base-content/50 mt-1">
            This identifier is used to automatically detect when this train is active in the simulator.
          </p>
        </div>
        <div class="flex items-center gap-3 mt-4">
          <span :if={@is_active} class="badge badge-success badge-sm gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-success-content animate-pulse" /> Active
          </span>
          <button type="submit" class="btn btn-primary btn-sm ml-auto">
            <.icon name="hero-check" class="w-4 h-4" />
            {if @new_mode, do: "Create Train", else: "Save"}
          </button>
        </div>
      </.form>
    </header>
    """
  end

  attr :elements, :list, required: true
  attr :is_active, :boolean, required: true

  defp elements_section(assigns) do
    ~H"""
    <div class="mb-6">
      <h3 class="text-base font-semibold mb-4">Elements</h3>

      <.empty_elements_state :if={Enum.empty?(@elements)} />

      <div :if={not Enum.empty?(@elements)} class="space-y-3">
        <.element_card :for={element <- @elements} element={element} is_active={@is_active} />
      </div>

      <button phx-click="open_add_element_modal" class="btn btn-outline btn-sm mt-4">
        <.icon name="hero-plus" class="w-4 h-4" /> Add Element
      </button>
    </div>
    """
  end

  defp empty_elements_state(assigns) do
    ~H"""
    <.empty_collection_state
      icon="hero-adjustments-horizontal"
      message="No elements configured"
      submessage="Add elements to control train functions"
    />
    """
  end

  attr :element, :map, required: true
  attr :is_active, :boolean, required: true

  defp element_card(assigns) do
    lever_config = get_lever_config(assigns.element)
    is_calibrated = lever_config != nil and lever_config.calibrated_at != nil
    notch_count = if lever_config, do: length(lever_config.notches || []), else: 0
    input_binding = get_input_binding(lever_config)
    has_input_ranges = has_notch_input_ranges?(lever_config)

    assigns =
      assigns
      |> assign(:lever_config, lever_config)
      |> assign(:is_calibrated, is_calibrated)
      |> assign(:notch_count, notch_count)
      |> assign(:input_binding, input_binding)
      |> assign(:has_input_ranges, has_input_ranges)

    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 p-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <.icon name="hero-adjustments-vertical" class="w-5 h-5 text-base-content/50" />
            <h4 class="font-medium">{@element.name}</h4>
            <span class="badge badge-ghost badge-sm capitalize">{@element.type}</span>
          </div>

          <%!-- Configuration Progress Stepper --%>
          <div class="mt-3 flex items-center gap-2 text-xs">
            <div class={[
              "flex items-center gap-1 px-2 py-1 rounded",
              if(@lever_config,
                do: "bg-success/10 text-success",
                else: "bg-base-200 text-base-content/50"
              )
            ]}>
              <.icon
                name={if @lever_config, do: "hero-check-circle", else: "hero-cog-6-tooth"}
                class="w-3.5 h-3.5"
              />
              <span>Endpoints</span>
            </div>
            <.icon name="hero-chevron-right" class="w-3 h-3 text-base-content/30" />
            <div class={[
              "flex items-center gap-1 px-2 py-1 rounded",
              cond do
                @input_binding -> "bg-success/10 text-success"
                @lever_config -> "bg-primary/10 text-primary"
                true -> "bg-base-200 text-base-content/50"
              end
            ]}>
              <.icon
                name={if @input_binding, do: "hero-check-circle", else: "hero-link"}
                class="w-3.5 h-3.5"
              />
              <span>Input</span>
            </div>
            <.icon name="hero-chevron-right" class="w-3 h-3 text-base-content/30" />
            <div class={[
              "flex items-center gap-1 px-2 py-1 rounded",
              cond do
                @has_input_ranges -> "bg-success/10 text-success"
                @input_binding -> "bg-primary/10 text-primary"
                true -> "bg-base-200 text-base-content/50"
              end
            ]}>
              <.icon
                name={if @has_input_ranges, do: "hero-check-circle", else: "hero-queue-list"}
                class="w-3.5 h-3.5"
              />
              <span>Mapping</span>
            </div>
          </div>

          <%!-- Status indicators --%>
          <div
            :if={@lever_config && !@input_binding}
            class="mt-3 p-2 bg-warning/10 border border-warning/30 rounded-lg"
          >
            <div class="flex items-start gap-2">
              <.icon
                name="hero-exclamation-triangle"
                class="w-4 h-4 text-warning flex-shrink-0 mt-0.5"
              />
              <div class="text-xs">
                <p class="font-medium text-warning">No hardware input bound</p>
                <p class="text-base-content/70">Bind a calibrated input to control this lever.</p>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-col items-end gap-2">
          <%!-- Primary actions --%>
          <div class="flex items-center gap-2">
            <button
              :if={@lever_config}
              phx-click="open_input_binding"
              phx-value-id={@element.id}
              class={[
                "btn btn-sm gap-1",
                if(@input_binding, do: "btn-outline btn-info", else: "btn-outline")
              ]}
            >
              <.icon name="hero-link" class="w-4 h-4" />
              {if @input_binding, do: "Change", else: "Bind Input"}
            </button>
            <button
              :if={@lever_config && @input_binding}
              phx-click="open_guided_notch_mapping"
              phx-value-id={@element.id}
              class="btn btn-sm btn-outline gap-1"
            >
              <.icon name="hero-queue-list" class="w-4 h-4" /> Map Notches
            </button>
          </div>
          <%!-- Secondary actions --%>
          <div class="flex items-center gap-1">
            <button
              phx-click="configure_lever"
              phx-value-id={@element.id}
              class="btn btn-ghost btn-xs text-base-content/60"
              title="Configure Endpoints"
            >
              <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
            </button>
            <button
              phx-click="delete_element"
              phx-value-id={@element.id}
              class="btn btn-ghost btn-xs text-error"
              title="Delete"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp get_lever_config(%Element{lever_config: %Ecto.Association.NotLoaded{}}), do: nil
  defp get_lever_config(%Element{lever_config: config}), do: config

  defp get_input_binding(nil), do: nil
  defp get_input_binding(%LeverConfig{input_binding: %Ecto.Association.NotLoaded{}}), do: nil
  defp get_input_binding(%LeverConfig{input_binding: nil}), do: nil

  defp get_input_binding(%LeverConfig{
         input_binding: %LeverInputBinding{input: %Ecto.Association.NotLoaded{}}
       }),
       do: nil

  defp get_input_binding(%LeverConfig{input_binding: binding}), do: binding

  defp has_notch_input_ranges?(nil), do: false

  defp has_notch_input_ranges?(%LeverConfig{notches: notches}) when is_list(notches) do
    Enum.any?(notches, fn notch ->
      notch.input_min != nil and notch.input_max != nil
    end)
  end

  defp has_notch_input_ranges?(_), do: false

  defp get_bound_input_port(%Element{lever_config: lever_config}) do
    case get_input_binding(lever_config) do
      %LeverInputBinding{input: %{device: %{config_id: config_id}}} ->
        find_port_for_device_config(config_id)

      _ ->
        nil
    end
  end

  defp get_bound_input_pin(%Element{lever_config: lever_config}) do
    case get_input_binding(lever_config) do
      %LeverInputBinding{input: %{pin: pin}} -> pin
      _ -> nil
    end
  end

  defp get_bound_input_calibration(%Element{lever_config: lever_config}) do
    case get_input_binding(lever_config) do
      %LeverInputBinding{input: %{calibration: calibration}} -> calibration
      _ -> nil
    end
  end

  defp find_port_for_device_config(config_id) when is_integer(config_id) do
    alias TswIo.Serial.Connection, as: SerialConnection

    SerialConnection.list_devices()
    |> Enum.find_value(fn device_conn ->
      if device_conn.device_config_id == config_id and device_conn.status == :connected do
        device_conn.port
      end
    end)
  end

  defp find_port_for_device_config(_), do: nil

  attr :form, :map, required: true

  defp add_element_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/50" phx-click="close_add_element_modal" />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-md mx-4 p-6">
        <h2 class="text-xl font-semibold mb-4">Add Element</h2>

        <.form for={@form} phx-change="validate_element" phx-submit="add_element">
          <div class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text">Element Name</span>
              </label>
              <.input
                field={@form[:name]}
                type="text"
                placeholder="e.g., Throttle, Reverser"
                class="input input-bordered w-full"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text">Type</span>
              </label>
              <.input
                field={@form[:type]}
                type="select"
                options={[{"Lever", :lever}]}
                class="select select-bordered w-full"
              />
              <p class="text-xs text-base-content/50 mt-1">
                More element types coming soon
              </p>
            </div>
          </div>

          <div class="flex justify-end gap-2 mt-6">
            <button type="button" phx-click="close_add_element_modal" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              Add Element
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :element, :map, required: true
  attr :form, :map, required: true
  attr :simulator_connected, :boolean, required: true

  defp lever_config_modal(assigns) do
    has_existing_config = assigns.element.lever_config != nil
    assigns = assign(assigns, :has_existing_config, has_existing_config)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/50" phx-click="close_lever_config_modal" />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-lg mx-4 p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-xl font-semibold mb-1">Configure {@element.name}</h2>
        <p class="text-sm text-base-content/60 mb-4">
          Set the simulator API endpoints for this lever control.
        </p>

        <.form for={@form} phx-change="validate_lever_config" phx-submit="save_lever_config">
          <div class="space-y-4">
            <div class="bg-base-200/50 rounded-lg p-4">
              <h3 class="text-sm font-semibold mb-3">Required Endpoints</h3>
              <div class="space-y-3">
                <.endpoint_input
                  form={@form}
                  field={:min_endpoint}
                  label="Minimum Value Endpoint"
                  placeholder="e.g., CurrentDrivableActor/Throttle(Lever).MinInput"
                  simulator_connected={@simulator_connected}
                />
                <.endpoint_input
                  form={@form}
                  field={:max_endpoint}
                  label="Maximum Value Endpoint"
                  placeholder="e.g., CurrentDrivableActor/Throttle(Lever).MaxInput"
                  simulator_connected={@simulator_connected}
                />
                <.endpoint_input
                  form={@form}
                  field={:value_endpoint}
                  label="Current Value Endpoint"
                  placeholder="e.g., CurrentDrivableActor/Throttle(Lever).InputValue"
                  simulator_connected={@simulator_connected}
                />
              </div>
            </div>

            <div class="bg-base-200/50 rounded-lg p-4">
              <h3 class="text-sm font-semibold mb-1">Optional: Notch Endpoints</h3>
              <p class="text-xs text-base-content/60 mb-3">
                If the lever has discrete notch positions, provide these endpoints.
              </p>
              <div class="space-y-3">
                <.endpoint_input
                  form={@form}
                  field={:notch_count_endpoint}
                  label="Notch Count Endpoint"
                  placeholder="e.g., CurrentDrivableActor/Throttle(Lever).NotchCount"
                  simulator_connected={@simulator_connected}
                />
                <.endpoint_input
                  form={@form}
                  field={:notch_index_endpoint}
                  label="Current Notch Index Endpoint"
                  placeholder="e.g., CurrentDrivableActor/Throttle(Lever).CurrentNotch"
                  simulator_connected={@simulator_connected}
                />
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-2 mt-6">
            <button type="button" phx-click="close_lever_config_modal" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              {if @has_existing_config, do: "Update Configuration", else: "Save Configuration"}
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :simulator_connected, :boolean, required: true

  defp endpoint_input(assigns) do
    ~H"""
    <div>
      <label class="label py-1">
        <span class="label-text text-xs">{@label}</span>
      </label>
      <div class="flex gap-2">
        <.input
          field={@form[@field]}
          type="text"
          placeholder={@placeholder}
          class="input input-bordered input-sm flex-1 font-mono text-xs"
        />
        <button
          type="button"
          phx-click="open_api_explorer"
          phx-value-field={@field}
          class="btn btn-ghost btn-sm"
          title={if @simulator_connected, do: "Browse API", else: "Connect simulator to browse API"}
          disabled={not @simulator_connected}
        >
          <.icon name="hero-folder-open" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :element, :map, required: true
  attr :notch_forms, :list, required: true
  attr :auto_detecting, :boolean, required: true
  attr :simulator_connected, :boolean, required: true

  defp notch_mapping_modal(assigns) do
    has_notch_endpoints = assigns.element.lever_config.notch_count_endpoint != nil
    assigns = assign(assigns, :has_notch_endpoints, has_notch_endpoints)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/50" phx-click="close_notch_mapping" />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-2xl max-h-[90vh] flex flex-col">
        <div class="p-6 border-b border-base-300">
          <h2 class="text-xl font-semibold">Map Notches - {@element.name}</h2>
          <p class="text-sm text-base-content/60 mt-1">
            Define discrete notch positions and their simulator API values.
          </p>
        </div>

        <div class="flex-1 overflow-y-auto p-6">
          <div :if={@simulator_connected and @has_notch_endpoints} class="mb-6">
            <div class="bg-primary/10 border border-primary/30 rounded-lg p-4">
              <div class="flex items-start justify-between gap-4">
                <div class="flex-1">
                  <h3 class="text-sm font-semibold flex items-center gap-2">
                    <.icon name="hero-sparkles" class="w-4 h-4" /> Auto-Detection Available
                  </h3>
                  <p class="text-xs text-base-content/70 mt-1">
                    The simulator is connected and notch endpoints are configured.
                    Click to automatically detect notch positions.
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="auto_detect_notches"
                  disabled={@auto_detecting}
                  class="btn btn-primary btn-sm"
                >
                  <.icon :if={not @auto_detecting} name="hero-sparkles" class="w-4 h-4" />
                  <span :if={@auto_detecting} class="loading loading-spinner loading-xs" />
                  {if @auto_detecting, do: "Detecting...", else: "Auto-Detect"}
                </button>
              </div>
            </div>
          </div>

          <div :if={not @has_notch_endpoints} class="mb-6">
            <div class="alert alert-info">
              <.icon name="hero-information-circle" class="w-5 h-5" />
              <div class="text-sm">
                <p class="font-medium">Optional: Configure notch endpoints for auto-detection</p>
                <p class="text-base-content/70">
                  To use auto-detection, add notch count and index endpoints in the lever configuration.
                  Or add notches manually below.
                </p>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="text-sm font-semibold">
                Notches ({length(@notch_forms)})
              </h3>
              <div class="flex items-center gap-2">
                <button
                  :if={not Enum.empty?(@notch_forms)}
                  type="button"
                  phx-click="auto_distribute_ranges"
                  class="btn btn-ghost btn-xs text-info"
                  title="Evenly distribute input ranges across all notches"
                >
                  <.icon name="hero-arrows-pointing-out" class="w-4 h-4" /> Auto-Distribute
                </button>
                <button
                  type="button"
                  phx-click="add_notch"
                  class="btn btn-ghost btn-xs text-primary"
                >
                  <.icon name="hero-plus" class="w-4 h-4" /> Add Notch
                </button>
              </div>
            </div>

            <div :if={Enum.empty?(@notch_forms)} class="text-center py-8 text-base-content/50">
              <.icon name="hero-queue-list" class="w-12 h-12 mx-auto mb-2 opacity-30" />
              <p class="text-sm">No notches defined yet</p>
              <p class="text-xs">Click "Add Notch" or use auto-detection to get started</p>
            </div>

            <div :if={not Enum.empty?(@notch_forms)} class="space-y-3">
              <div
                :for={{form, index} <- Enum.with_index(@notch_forms)}
                class="bg-base-200/50 rounded-lg p-4"
              >
                <.form
                  :let={f}
                  for={form}
                  phx-change="validate_notch"
                  phx-value-index={index}
                  id={"notch-form-#{index}"}
                >
                  <div class="flex items-start gap-3">
                    <div class="flex-none w-12 pt-6 text-center">
                      <span class="text-sm font-semibold text-base-content/50">#{index}</span>
                    </div>

                    <div class="flex-1 space-y-3">
                      <div class="grid grid-cols-2 gap-3">
                        <div>
                          <label class="label py-1">
                            <span class="label-text text-xs">Type</span>
                          </label>
                          <.input
                            field={f[:type]}
                            type="select"
                            options={[{"Gate (Fixed)", :gate}, {"Linear (Range)", :linear}]}
                            class="select select-bordered select-sm w-full"
                          />
                        </div>
                        <div>
                          <label class="label py-1">
                            <span class="label-text text-xs">Description</span>
                          </label>
                          <.input
                            field={f[:description]}
                            type="text"
                            placeholder="e.g., Idle, Notch 1, Full Power"
                            class="input input-bordered input-sm w-full"
                          />
                        </div>
                      </div>

                      <div
                        :if={f[:type].value == "gate" or f[:type].value == :gate}
                        class="grid grid-cols-1"
                      >
                        <div>
                          <label class="label py-1">
                            <span class="label-text text-xs">Value</span>
                          </label>
                          <.input
                            field={f[:value]}
                            type="number"
                            step="0.001"
                            class="input input-bordered input-sm w-full font-mono"
                          />
                        </div>
                      </div>

                      <div
                        :if={f[:type].value == "linear" or f[:type].value == :linear}
                        class="grid grid-cols-2 gap-3"
                      >
                        <div>
                          <label class="label py-1">
                            <span class="label-text text-xs">Min Value</span>
                          </label>
                          <.input
                            field={f[:min_value]}
                            type="number"
                            step="0.001"
                            class="input input-bordered input-sm w-full font-mono"
                          />
                        </div>
                        <div>
                          <label class="label py-1">
                            <span class="label-text text-xs">Max Value</span>
                          </label>
                          <.input
                            field={f[:max_value]}
                            type="number"
                            step="0.001"
                            class="input input-bordered input-sm w-full font-mono"
                          />
                        </div>
                      </div>

                      <div class="border-t border-base-300 pt-3 mt-3">
                        <h4 class="text-xs font-medium text-base-content/60 mb-2">
                          Input Range (0.0-1.0)
                        </h4>
                        <div class="grid grid-cols-2 gap-3">
                          <div>
                            <label class="label py-1">
                              <span class="label-text text-xs">Input Min</span>
                            </label>
                            <.input
                              field={f[:input_min]}
                              type="number"
                              step="0.01"
                              min="0"
                              max="1"
                              placeholder="0.0"
                              class="input input-bordered input-sm w-full font-mono"
                            />
                          </div>
                          <div>
                            <label class="label py-1">
                              <span class="label-text text-xs">Input Max</span>
                            </label>
                            <.input
                              field={f[:input_max]}
                              type="number"
                              step="0.01"
                              min="0"
                              max="1"
                              placeholder="1.0"
                              class="input input-bordered input-sm w-full font-mono"
                            />
                          </div>
                        </div>
                      </div>
                    </div>

                    <div class="flex-none pt-6">
                      <button
                        type="button"
                        phx-click="remove_notch"
                        phx-value-index={index}
                        class="btn btn-ghost btn-xs btn-circle text-error"
                        title="Remove notch"
                      >
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>

        <div class="p-6 border-t border-base-300 flex justify-end gap-2">
          <button type="button" phx-click="close_notch_mapping" class="btn btn-ghost">
            Cancel
          </button>
          <button
            type="button"
            phx-click="save_notches"
            class="btn btn-primary"
            disabled={Enum.empty?(@notch_forms)}
          >
            <.icon name="hero-check" class="w-4 h-4" /> Save Notches
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :element, :map, required: true
  attr :available_inputs, :list, required: true

  defp input_binding_modal(assigns) do
    current_binding = get_input_binding(assigns.element.lever_config)
    assigns = assign(assigns, :current_binding, current_binding)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/50" phx-click="close_input_binding" />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-md max-h-[90vh] flex flex-col">
        <div class="p-6 border-b border-base-300">
          <h2 class="text-xl font-semibold">Bind Hardware Input</h2>
          <p class="text-sm text-base-content/60 mt-1">
            Select a calibrated input to control <strong>{@element.name}</strong>
          </p>
        </div>

        <div class="flex-1 overflow-y-auto p-6">
          <div :if={@current_binding} class="mb-4">
            <div class="bg-info/10 border border-info/30 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div>
                  <h3 class="text-sm font-semibold">Currently Bound</h3>
                  <p class="text-sm">
                    {@current_binding.input.device.name} - Pin {@current_binding.input.pin}
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="unbind_input"
                  class="btn btn-ghost btn-sm text-error"
                >
                  <.icon name="hero-link-slash" class="w-4 h-4" /> Unbind
                </button>
              </div>
            </div>
          </div>

          <div :if={Enum.empty?(@available_inputs)} class="text-center py-8 text-base-content/50">
            <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto mb-2 opacity-30" />
            <p class="text-sm">No calibrated inputs available</p>
            <p class="text-xs">Calibrate a device input first</p>
          </div>

          <div :if={not Enum.empty?(@available_inputs)} class="space-y-2">
            <h3 class="text-sm font-semibold mb-2">Available Inputs</h3>
            <button
              :for={input <- @available_inputs}
              type="button"
              phx-click="bind_input"
              phx-value-input_id={input.id}
              class={"w-full text-left p-3 rounded-lg border transition-colors " <>
                if(@current_binding && @current_binding.input_id == input.id,
                  do: "bg-info/10 border-info",
                  else: "bg-base-200/50 border-base-300 hover:bg-base-200")}
            >
              <div class="flex items-center justify-between">
                <div>
                  <p class="font-medium">{input.device.name}</p>
                  <p class="text-sm text-base-content/60">Pin {input.pin}</p>
                </div>
                <div :if={@current_binding && @current_binding.input_id == input.id}>
                  <.icon name="hero-check-circle" class="w-5 h-5 text-info" />
                </div>
              </div>
            </button>
          </div>
        </div>

        <div class="p-6 border-t border-base-300 flex justify-end">
          <button type="button" phx-click="close_input_binding" class="btn btn-ghost">
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end
end
