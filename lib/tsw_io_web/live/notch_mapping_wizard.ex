defmodule TswIoWeb.NotchMappingWizard do
  @moduledoc """
  LiveComponent for mapping physical lever positions to notch boundaries.

  The wizard guides the user through each boundary point:
  1. Move the physical lever to the position where the boundary should be
  2. Wait for the value to stabilize
  3. Click "Set" to capture the boundary
  4. Repeat for all boundaries
  5. Preview and save

  ## Usage

      <.live_component
        module={TswIoWeb.NotchMappingWizard}
        id="notch-mapping-wizard"
        lever_config={@lever_config}
        port={@port}
        pin={@pin}
        calibration={@calibration}
      />
  """

  use TswIoWeb, :live_component

  alias TswIo.Train
  alias TswIo.Train.Calibration.NotchMappingSession

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:session_pid, nil)
     |> assign(:session_state, nil)}
  end

  @impl true
  def update(%{lever_config: lever_config} = assigns, socket) do
    socket = assign(socket, assigns)

    # Update session_state if passed from parent
    socket =
      if Map.has_key?(assigns, :session_state) and assigns.session_state do
        assign(socket, :session_state, assigns.session_state)
      else
        socket
      end

    # Start session if we don't have one yet
    if is_nil(socket.assigns.session_pid) do
      NotchMappingSession.subscribe(lever_config.id)

      opts = [
        lever_config: lever_config,
        port: assigns.port,
        pin: assigns.pin,
        calibration: assigns.calibration
      ]

      case Train.start_notch_mapping(opts) do
        {:ok, pid} ->
          state = NotchMappingSession.get_public_state(pid)

          {:ok,
           socket
           |> assign(:session_pid, pid)
           |> assign(:session_state, state)}

        {:error, reason} ->
          send(self(), {:notch_mapping_error, reason})
          {:ok, socket}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("start_mapping", _params, socket) do
    case NotchMappingSession.start_mapping(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot start: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("capture_boundary", _params, socket) do
    case NotchMappingSession.capture_boundary(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, :unstable_value} ->
        {:noreply, put_flash(socket, :error, "Value not stable. Hold the lever steady.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot capture: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("go_to_boundary", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    case NotchMappingSession.go_to_boundary(socket.assigns.session_pid, index) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot go to boundary: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("go_to_preview", _params, socket) do
    case NotchMappingSession.go_to_preview(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, :incomplete_boundaries} ->
        {:noreply, put_flash(socket, :error, "Please set all boundary positions first.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot preview: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("save_mapping", _params, socket) do
    case NotchMappingSession.save_mapping(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot save: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    if socket.assigns.session_pid do
      NotchMappingSession.cancel(socket.assigns.session_pid)
    end

    send(self(), :notch_mapping_cancelled)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/50" phx-click="cancel" phx-target={@myself} />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-lg mx-4 p-6">
        <.wizard_header lever_config={@lever_config} target={@myself} />

        <.loading_state :if={is_nil(@session_state)} />

        <div :if={@session_state}>
          <.boundary_indicator
            :if={@session_state.current_step != :ready}
            session_state={@session_state}
          />

          <.step_content
            session_state={@session_state}
            myself={@myself}
          />
        </div>
      </div>
    </div>
    """
  end

  # Components

  attr :lever_config, :map, required: true
  attr :target, :any, required: true

  defp wizard_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="text-xl font-semibold">Map Input Ranges</h2>
        <p class="text-sm text-base-content/70">{@lever_config.element.name}</p>
      </div>
      <button
        phx-click="cancel"
        phx-target={@target}
        class="btn btn-ghost btn-sm btn-circle"
        aria-label="Close"
      >
        <.icon name="hero-x-mark" class="w-5 h-5" />
      </button>
    </div>
    """
  end

  defp loading_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12">
      <span class="loading loading-spinner loading-lg text-primary"></span>
      <p class="mt-4 text-base-content/70">Starting mapping session...</p>
    </div>
    """
  end

  attr :session_state, :map, required: true

  defp boundary_indicator(assigns) do
    state = assigns.session_state
    boundaries = state.captured_boundaries
    current_idx = state.current_boundary_index

    assigns =
      assigns
      |> assign(:boundaries, boundaries)
      |> assign(:current_idx, current_idx)

    ~H"""
    <div class="flex items-center justify-center gap-1 mb-6">
      <div :for={{value, index} <- Enum.with_index(@boundaries)} class="flex items-center">
        <div class={[
          "w-8 h-8 rounded-full flex items-center justify-center text-xs font-medium transition-colors cursor-pointer",
          boundary_class(value, index, @current_idx)
        ]}>
          <.icon :if={value != nil and index != @current_idx} name="hero-check" class="w-4 h-4" />
          <span :if={value == nil or index == @current_idx}>{index}</span>
        </div>
        <div
          :if={index < length(@boundaries) - 1}
          class={[
            "w-6 h-0.5 mx-0.5",
            notch_connector_class(index, @boundaries)
          ]}
        />
      </div>
    </div>
    """
  end

  defp boundary_class(nil, index, current_idx) when index == current_idx do
    "bg-primary text-primary-content ring-4 ring-primary/30"
  end

  defp boundary_class(nil, _index, _current_idx) do
    "bg-base-300 text-base-content/50"
  end

  defp boundary_class(_value, index, current_idx) when index == current_idx do
    "bg-primary text-primary-content ring-4 ring-primary/30"
  end

  defp boundary_class(_value, _index, _current_idx) do
    "bg-success text-success-content"
  end

  defp notch_connector_class(index, boundaries) do
    b1 = Enum.at(boundaries, index)
    b2 = Enum.at(boundaries, index + 1)

    if b1 != nil and b2 != nil do
      "bg-success"
    else
      "bg-base-300"
    end
  end

  attr :session_state, :map, required: true
  attr :myself, :any, required: true

  defp step_content(assigns) do
    ~H"""
    <div class="space-y-6">
      <.ready_step :if={@session_state.current_step == :ready} myself={@myself} />
      <.mapping_boundary_step
        :if={match?({:mapping_boundary, _}, @session_state.current_step)}
        state={@session_state}
        myself={@myself}
      />
      <.preview_step
        :if={@session_state.current_step == :preview}
        state={@session_state}
        myself={@myself}
      />
      <.saving_step :if={@session_state.current_step == :saving} />
      <.complete_step :if={@session_state.current_step == :complete} state={@session_state} />
    </div>
    """
  end

  attr :myself, :any, required: true

  defp ready_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-primary/10 flex items-center justify-center">
        <.icon name="hero-adjustments-horizontal" class="w-8 h-8 text-primary" />
      </div>
      <h3 class="text-lg font-semibold mb-2">Ready to Map Input Ranges</h3>
      <p class="text-base-content/70 mb-6">
        You'll set the physical lever position for each notch boundary.
        Move the lever and click "Set" when the value is stable.
      </p>

      <div class="flex justify-between gap-4 pt-4 border-t border-base-300">
        <button phx-click="cancel" phx-target={@myself} class="btn btn-ghost">
          Cancel
        </button>
        <button phx-click="start_mapping" phx-target={@myself} class="btn btn-primary">
          Start <.icon name="hero-arrow-right" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :myself, :any, required: true

  defp mapping_boundary_step(assigns) do
    state = assigns.state
    {:mapping_boundary, boundary_idx} = state.current_step

    boundary_description = get_boundary_description(boundary_idx, state)

    assigns =
      assigns
      |> assign(:boundary_idx, boundary_idx)
      |> assign(:boundary_description, boundary_description)

    ~H"""
    <div class="text-center">
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-info/10 flex items-center justify-center">
        <.icon name="hero-cursor-arrow-rays" class="w-8 h-8 text-info" />
      </div>
      <h3 class="text-lg font-semibold mb-2">Set Boundary {@boundary_idx}</h3>
      <p class="text-base-content/70 mb-4">
        {@boundary_description}
      </p>

      <.live_value_display state={@state} />

      <.stability_indicator state={@state} />

      <div class="flex justify-between gap-4 pt-4 border-t border-base-300">
        <button phx-click="cancel" phx-target={@myself} class="btn btn-ghost">
          Cancel
        </button>
        <div class="flex gap-2">
          <button
            :if={@state.all_captured}
            phx-click="go_to_preview"
            phx-target={@myself}
            class="btn btn-outline"
          >
            Preview
          </button>
          <button
            phx-click="capture_boundary"
            phx-target={@myself}
            disabled={!@state.can_capture}
            class="btn btn-primary"
          >
            Set Boundary <.icon name="hero-check" class="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true

  defp live_value_display(assigns) do
    value = assigns.state.current_value

    assigns = assign(assigns, :value, value)

    ~H"""
    <div class="bg-base-200 rounded-lg p-6 mb-4">
      <div class="text-4xl font-mono font-bold text-primary">
        {if @value, do: format_value(@value), else: "---"}
      </div>
      <div class="text-sm text-base-content/70 mt-1">Current Position</div>
    </div>
    """
  end

  attr :state, :map, required: true

  defp stability_indicator(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-4 text-sm">
      <div class={[
        "flex items-center gap-1",
        if(@state.sample_count >= 5, do: "text-success", else: "text-base-content/50")
      ]}>
        <.icon
          name={if @state.sample_count >= 5, do: "hero-check-circle", else: "hero-clock"}
          class="w-4 h-4"
        />
        <span>{@state.sample_count}/5 samples</span>
      </div>
      <div class={[
        "flex items-center gap-1",
        if(@state.is_stable, do: "text-success", else: "text-base-content/50")
      ]}>
        <.icon
          name={if @state.is_stable, do: "hero-check-circle", else: "hero-arrow-path"}
          class="w-4 h-4"
        />
        <span>{if @state.is_stable, do: "Stable", else: "Stabilizing..."}</span>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :myself, :any, required: true

  defp preview_step(assigns) do
    state = assigns.state
    boundaries = Enum.sort(state.captured_boundaries)

    notch_ranges =
      state.notch_descriptions
      |> Enum.with_index()
      |> Enum.map(fn {desc, idx} ->
        %{
          description: desc,
          input_min: Enum.at(boundaries, idx),
          input_max: Enum.at(boundaries, idx + 1)
        }
      end)

    assigns = assign(assigns, :notch_ranges, notch_ranges)

    ~H"""
    <div>
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-success/10 flex items-center justify-center">
        <.icon name="hero-clipboard-document-check" class="w-8 h-8 text-success" />
      </div>
      <h3 class="text-lg font-semibold mb-2 text-center">Preview Mapping</h3>
      <p class="text-base-content/70 mb-4 text-center">
        Review the notch input ranges before saving.
      </p>

      <div class="space-y-2 mb-6">
        <div
          :for={{notch, idx} <- Enum.with_index(@notch_ranges)}
          class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
        >
          <div class="flex items-center gap-3">
            <span class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-medium">
              {idx}
            </span>
            <span class="font-medium">{notch.description}</span>
          </div>
          <div class="font-mono text-sm">
            {format_value(notch.input_min)} - {format_value(notch.input_max)}
          </div>
        </div>
      </div>

      <div class="flex justify-between gap-4 pt-4 border-t border-base-300">
        <button
          phx-click="go_to_boundary"
          phx-value-index="0"
          phx-target={@myself}
          class="btn btn-ghost"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4" /> Edit
        </button>
        <button phx-click="save_mapping" phx-target={@myself} class="btn btn-primary">
          Save Mapping <.icon name="hero-check" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  defp saving_step(assigns) do
    ~H"""
    <div class="text-center py-8">
      <span class="loading loading-spinner loading-lg text-primary"></span>
      <p class="mt-4 text-base-content/70">Saving mapping...</p>
    </div>
    """
  end

  attr :state, :map, required: true

  defp complete_step(assigns) do
    ~H"""
    <div class="text-center">
      <div :if={match?({:ok, _}, @state.result)} class="space-y-4">
        <div class="w-16 h-16 mx-auto rounded-full bg-success/10 flex items-center justify-center">
          <.icon name="hero-check-circle" class="w-8 h-8 text-success" />
        </div>
        <h3 class="text-lg font-semibold">Mapping Complete!</h3>
        <p class="text-base-content/70">
          Input ranges have been saved for all notches.
        </p>
      </div>

      <div :if={match?({:error, _}, @state.result)} class="space-y-4">
        <div class="w-16 h-16 mx-auto rounded-full bg-error/10 flex items-center justify-center">
          <.icon name="hero-exclamation-circle" class="w-8 h-8 text-error" />
        </div>
        <h3 class="text-lg font-semibold">Mapping Failed</h3>
        <p class="text-base-content/70">
          {format_error(@state.result)}
        </p>
      </div>
    </div>
    """
  end

  # Helpers

  defp get_boundary_description(0, state) do
    notch_desc = List.first(state.notch_descriptions) || "Notch 0"
    "Move lever to the START of #{notch_desc}"
  end

  defp get_boundary_description(idx, state) when idx >= state.notch_count do
    notch_desc = List.last(state.notch_descriptions) || "Notch #{state.notch_count - 1}"
    "Move lever to the END of #{notch_desc}"
  end

  defp get_boundary_description(idx, state) do
    prev_notch = Enum.at(state.notch_descriptions, idx - 1) || "Notch #{idx - 1}"
    next_notch = Enum.at(state.notch_descriptions, idx) || "Notch #{idx}"
    "Move lever to boundary between #{prev_notch} and #{next_notch}"
  end

  defp format_value(nil), do: "---"
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)

  defp format_error({:error, reason}) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error({:error, reason}), do: inspect(reason)
  defp format_error(_), do: "Unknown error"
end
