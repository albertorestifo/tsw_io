defmodule TswIoWeb.TrainListLive do
  @moduledoc """
  LiveView for listing and managing train configurations.

  Displays all saved train configurations and highlights the currently
  active train based on the simulator connection.
  """

  use TswIoWeb, :live_view

  import TswIoWeb.NavComponents
  import TswIoWeb.SharedComponents

  alias TswIo.Train, as: TrainContext
  alias TswIo.Serial.Connection

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      TrainContext.subscribe()
    end

    trains = TrainContext.list_trains(preload: [:elements])
    current_identifier = TrainContext.get_current_identifier()
    active_train = TrainContext.get_active_train()

    {:ok,
     socket
     |> assign(:trains, trains)
     |> assign(:current_identifier, current_identifier)
     |> assign(:active_train, active_train)}
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
  def handle_info({:train_detected, %{identifier: identifier, train: train}}, socket) do
    {:noreply,
     socket
     |> assign(:current_identifier, identifier)
     |> assign(:active_train, train)}
  end

  @impl true
  def handle_info({:train_changed, train}, socket) do
    {:noreply, assign(socket, :active_train, train)}
  end

  @impl true
  def handle_info({:detection_error, _reason}, socket) do
    {:noreply, socket}
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
    active_train_id =
      if assigns.active_train, do: assigns.active_train.id, else: nil

    assigns = assign(assigns, :active_train_id, active_train_id)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.nav_header
        devices={@nav_devices}
        simulator_status={@nav_simulator_status}
        firmware_update={@nav_firmware_update}
        app_version_update={@nav_app_version_update}
        firmware_checking={@nav_firmware_checking}
        dropdown_open={@nav_dropdown_open}
        scanning={@nav_scanning}
        current_path={@nav_current_path}
      />

      <main class="flex-1 p-4 sm:p-8">
        <div class="max-w-2xl mx-auto">
          <.page_header
            title="Trains"
            subtitle="Manage train configurations"
            action_path={~p"/trains/new"}
            action_text="New Train"
          />

          <.unconfigured_banner
            :if={@current_identifier && @active_train == nil}
            identifier={@current_identifier}
          />

          <.empty_state
            :if={Enum.empty?(@trains)}
            icon="hero-truck"
            heading="No Train Configurations"
            description="Create a train configuration to set up controls for your simulator trains."
            action_path={~p"/trains/new"}
            action_text="Create Train Configuration"
          />

          <div :if={not Enum.empty?(@trains)} class="space-y-4">
            <.list_card
              :for={train <- @trains}
              active={train.id == @active_train_id}
              navigate_to={~p"/trains/#{train.id}"}
              title={train.name}
              description={train.description}
              metadata={[train.identifier, element_count_text(length(train.elements))]}
            />
          </div>
        </div>
      </main>
    </div>
    """
  end

  attr :identifier, :string, required: true

  defp unconfigured_banner(assigns) do
    ~H"""
    <div class="alert alert-info mb-6">
      <.icon name="hero-information-circle" class="w-5 h-5" />
      <div class="flex-1">
        <h3 class="font-semibold">Train Detected</h3>
        <p class="text-sm">
          A train with identifier "<span class="font-mono">{@identifier}</span>" is connected but not configured.
        </p>
      </div>
      <.link navigate={~p"/trains/new?identifier=#{@identifier}"} class="btn btn-sm btn-primary">
        Configure
      </.link>
    </div>
    """
  end

  defp element_count_text(0), do: "No elements"
  defp element_count_text(1), do: "1 element"
  defp element_count_text(n), do: "#{n} elements"
end
