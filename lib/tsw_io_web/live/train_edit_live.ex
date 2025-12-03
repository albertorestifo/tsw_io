defmodule TswIoWeb.TrainEditLive do
  @moduledoc """
  LiveView for editing a train configuration.

  Supports both creating new trains and editing existing ones.
  Allows managing train elements (levers, etc.) and their configurations.
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents
  import TswIoWeb.SharedComponents

  alias TswIo.Train, as: TrainContext
  alias TswIo.Train.{Train, Element, LeverConfig, Notch}
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
     |> assign(:api_explorer_field, nil)}
  end

  defp mount_existing(socket, train_id) do
    case TrainContext.get_train(train_id, preload: [elements: [lever_config: :notches]]) do
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
         |> assign(:api_explorer_field, nil)}

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

    assigns =
      assigns
      |> assign(:lever_config, lever_config)
      |> assign(:is_calibrated, is_calibrated)
      |> assign(:notch_count, notch_count)

    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 p-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <.icon name="hero-adjustments-vertical" class="w-5 h-5 text-base-content/50" />
            <h4 class="font-medium">{@element.name}</h4>
            <span class="badge badge-ghost badge-sm capitalize">{@element.type}</span>
          </div>

          <div class="mt-2 flex items-center gap-4 text-xs text-base-content/60">
            <span :if={@lever_config}>
              {notch_text(@notch_count)}
            </span>
            <span :if={@is_calibrated} class="text-success flex items-center gap-1">
              <.icon name="hero-check-circle" class="w-3 h-3" /> Calibrated
            </span>
            <span :if={not @is_calibrated} class="text-warning flex items-center gap-1">
              <.icon name="hero-exclamation-triangle" class="w-3 h-3" /> Not calibrated
            </span>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <button
            :if={@lever_config}
            phx-click="open_notch_mapping"
            phx-value-id={@element.id}
            class="btn btn-ghost btn-xs text-primary"
            title="Map Notches"
          >
            <.icon name="hero-queue-list" class="w-4 h-4" />
          </button>
          <button
            phx-click="configure_lever"
            phx-value-id={@element.id}
            class="btn btn-ghost btn-xs text-primary"
            title="Configure"
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
    """
  end

  defp get_lever_config(%Element{lever_config: %Ecto.Association.NotLoaded{}}), do: nil
  defp get_lever_config(%Element{lever_config: config}), do: config

  defp notch_text(0), do: "No notches"
  defp notch_text(1), do: "1 notch"
  defp notch_text(n), do: "#{n} notches"

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
              <button
                type="button"
                phx-click="add_notch"
                class="btn btn-ghost btn-xs text-primary"
              >
                <.icon name="hero-plus" class="w-4 h-4" /> Add Notch
              </button>
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
end
