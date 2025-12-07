defmodule TswIoWeb.NotchMappingWizard do
  @moduledoc """
  LiveComponent for mapping physical lever positions to notch input ranges.

  The wizard guides the user through each notch:
  1. For gate notches: Wiggle the lever in the detent to capture the range
  2. For linear notches: Sweep the lever through the full range
  3. System tracks min/max of all samples
  4. Click "Capture" to save the range and move to next notch
  5. Preview and save

  Values are displayed as calibrated integers (0 to total_travel) for precision,
  and converted to normalized 0.0-1.0 when saved.
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
  def handle_event("capture_range", _params, socket) do
    case NotchMappingSession.capture_range(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, :not_enough_samples} ->
        {:noreply, put_flash(socket, :error, "Need more samples. Keep moving the lever.")}

      {:error, :no_range_detected} ->
        {:noreply,
         put_flash(socket, :error, "No range detected. Move the lever through the notch range.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot capture: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reset_samples", _params, socket) do
    case NotchMappingSession.reset_samples(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot reset: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_capturing", _params, socket) do
    case NotchMappingSession.start_capturing(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot start capturing: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop_capturing", _params, socket) do
    case NotchMappingSession.stop_capturing(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot stop capturing: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("go_to_notch", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    case NotchMappingSession.go_to_notch(socket.assigns.session_pid, index) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot go to notch: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("go_to_preview", _params, socket) do
    case NotchMappingSession.go_to_preview(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, :incomplete_ranges} ->
        {:noreply, put_flash(socket, :error, "Please capture all notch ranges first.")}

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

  # Keep old event for compatibility
  @impl true
  def handle_event("capture_boundary", params, socket) do
    handle_event("capture_range", params, socket)
  end

  @impl true
  def handle_event("go_to_boundary", params, socket) do
    handle_event("go_to_notch", params, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/50" phx-click="cancel" phx-target={@myself} />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-lg max-h-[90vh] flex flex-col overflow-hidden">
        <div class="p-6 pb-0 flex-shrink-0">
          <.wizard_header element_name={@element_name} target={@myself} />
        </div>

        <div class="flex-1 overflow-y-auto p-6 pt-0">
          <.loading_state :if={is_nil(@session_state)} />

          <div :if={@session_state}>
            <.notch_indicator
              :if={@session_state.current_step != :ready}
              session_state={@session_state}
              myself={@myself}
            />

            <.step_content
              session_state={@session_state}
              myself={@myself}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Components

  attr :element_name, :string, required: true
  attr :target, :any, required: true

  defp wizard_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="text-xl font-semibold">Map Input Ranges</h2>
        <p class="text-sm text-base-content/70">{@element_name}</p>
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
  attr :myself, :any, required: true

  defp notch_indicator(assigns) do
    state = assigns.session_state
    notches = state.notches
    ranges = state.captured_ranges
    current_idx = state.current_notch_index

    assigns =
      assigns
      |> assign(:notches, notches)
      |> assign(:ranges, ranges)
      |> assign(:current_idx, current_idx)

    ~H"""
    <div class="flex items-center justify-center gap-1 mb-6 flex-wrap">
      <div :for={{notch, idx} <- Enum.with_index(@notches)} class="flex items-center">
        <button
          phx-click="go_to_notch"
          phx-value-index={idx}
          phx-target={@myself}
          class={[
            "w-8 h-8 rounded-full flex items-center justify-center text-xs font-medium transition-colors",
            notch_indicator_class(Enum.at(@ranges, idx), idx, @current_idx)
          ]}
        >
          <.icon
            :if={Enum.at(@ranges, idx) != nil and idx != @current_idx}
            name="hero-check"
            class="w-4 h-4"
          />
          <span :if={Enum.at(@ranges, idx) == nil or idx == @current_idx}>{idx}</span>
        </button>
        <div
          :if={idx < length(@notches) - 1}
          class="w-4 h-0.5 mx-0.5 bg-base-300"
        />
      </div>
    </div>
    """
  end

  defp notch_indicator_class(nil, index, current_idx) when index == current_idx do
    "bg-primary text-primary-content ring-4 ring-primary/30"
  end

  defp notch_indicator_class(nil, _index, _current_idx) do
    "bg-base-300 text-base-content/50 hover:bg-base-200"
  end

  defp notch_indicator_class(_range, index, current_idx) when index == current_idx do
    "bg-primary text-primary-content ring-4 ring-primary/30"
  end

  defp notch_indicator_class(_range, _index, _current_idx) do
    "bg-success text-success-content hover:bg-success/80"
  end

  attr :session_state, :map, required: true
  attr :myself, :any, required: true

  defp step_content(assigns) do
    ~H"""
    <div class="space-y-6">
      <.ready_step :if={@session_state.current_step == :ready} myself={@myself} />
      <.mapping_notch_step
        :if={match?({:mapping_notch, _}, @session_state.current_step)}
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
        For each notch, you'll move the lever to define its input range.
        The system will track the minimum and maximum positions.
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

  defp mapping_notch_step(assigns) do
    state = assigns.state
    notch = state.current_notch

    assigns =
      assigns
      |> assign(:notch, notch)
      |> assign(:is_capturing, state.is_capturing)

    ~H"""
    <div class="text-center">
      <%= if @is_capturing do %>
        <.capturing_view state={@state} notch={@notch} myself={@myself} />
      <% else %>
        <.positioning_view state={@state} notch={@notch} myself={@myself} />
      <% end %>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :notch, :map, required: true
  attr :myself, :any, required: true

  defp positioning_view(assigns) do
    ~H"""
    <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-base-300 flex items-center justify-center">
      <.icon name="hero-arrow-path" class="w-8 h-8 text-base-content/70" />
    </div>
    <h3 class="text-lg font-semibold mb-2">{@notch.description} — Position Lever</h3>
    <p class="text-base-content/70 mb-4">
      Move the lever to the {@notch.description} position, then start capturing.
    </p>

    <.position_display state={@state} />

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
          phx-click="start_capturing"
          phx-target={@myself}
          class="btn btn-primary"
        >
          Start Capturing <.icon name="hero-play" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :notch, :map, required: true
  attr :myself, :any, required: true

  defp capturing_view(assigns) do
    instruction = get_notch_instruction(assigns.notch)
    assigns = assign(assigns, :instruction, instruction)

    ~H"""
    <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-warning/20 flex items-center justify-center">
      <span class="relative flex h-4 w-4">
        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-warning opacity-75">
        </span>
        <span class="relative inline-flex rounded-full h-4 w-4 bg-warning"></span>
      </span>
    </div>
    <h3 class="text-lg font-semibold mb-2">{@notch.description} — Capturing...</h3>
    <p class="text-base-content/70 mb-4">
      {@instruction}
    </p>

    <.range_display state={@state} />

    <.sample_indicator state={@state} myself={@myself} />

    <div class="flex justify-between gap-4 pt-4 border-t border-base-300">
      <button phx-click="stop_capturing" phx-target={@myself} class="btn btn-ghost">
        <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> Stop & Retry
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
          phx-click="capture_range"
          phx-target={@myself}
          disabled={!@state.can_capture}
          class="btn btn-primary"
        >
          Complete <.icon name="hero-check" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true

  defp position_display(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4 mb-4">
      <div class="text-center">
        <div class="text-3xl font-mono font-bold text-primary">
          {format_calibrated(@state.current_value)}
        </div>
        <div class="text-xs text-base-content/70 mt-1">Current Position</div>
      </div>
      <div class="mt-2 text-xs text-base-content/50 text-center">
        Total travel: {@state.total_travel}
      </div>
    </div>
    """
  end

  attr :state, :map, required: true

  defp range_display(assigns) do
    state = assigns.state
    total = state.total_travel

    assigns =
      assigns
      |> assign(:total, total)

    ~H"""
    <div class="bg-base-200 rounded-lg p-4 mb-4">
      <div class="grid grid-cols-3 gap-4 text-center">
        <div>
          <div class="text-2xl font-mono font-bold text-info">
            {format_calibrated(@state.current_min)}
          </div>
          <div class="text-xs text-base-content/70">Min</div>
        </div>
        <div>
          <div class="text-3xl font-mono font-bold text-primary">
            {format_calibrated(@state.current_value)}
          </div>
          <div class="text-xs text-base-content/70">Current</div>
        </div>
        <div>
          <div class="text-2xl font-mono font-bold text-info">
            {format_calibrated(@state.current_max)}
          </div>
          <div class="text-xs text-base-content/70">Max</div>
        </div>
      </div>
      <div class="mt-2 text-xs text-base-content/50 text-center">
        Total travel: {@total}
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :myself, :any, required: true

  defp sample_indicator(assigns) do
    min_samples = 10

    assigns = assign(assigns, :min_samples, min_samples)

    ~H"""
    <div class="flex items-center justify-center gap-4 text-sm">
      <div class={[
        "flex items-center gap-1",
        if(@state.sample_count >= @min_samples, do: "text-success", else: "text-base-content/50")
      ]}>
        <.icon
          name={if @state.sample_count >= @min_samples, do: "hero-check-circle", else: "hero-clock"}
          class="w-4 h-4"
        />
        <span>{@state.sample_count}/{@min_samples} samples</span>
      </div>
      <div
        :if={@state.current_min != nil and @state.current_max != nil}
        class="flex items-center gap-1 text-info"
      >
        <.icon name="hero-arrows-right-left" class="w-4 h-4" />
        <span>Range: {format_calibrated(@state.current_max - @state.current_min)}</span>
      </div>
      <button
        :if={@state.sample_count > 0}
        phx-click="reset_samples"
        phx-target={@myself}
        class="btn btn-ghost btn-xs"
      >
        Reset
      </button>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :myself, :any, required: true

  defp preview_step(assigns) do
    state = assigns.state

    notch_data =
      state.notches
      |> Enum.with_index()
      |> Enum.map(fn {notch, idx} ->
        range = Enum.at(state.captured_ranges, idx)
        Map.put(notch, :range, range)
      end)

    assigns = assign(assigns, :notch_data, notch_data)

    ~H"""
    <div>
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-success/10 flex items-center justify-center">
        <.icon name="hero-clipboard-document-check" class="w-8 h-8 text-success" />
      </div>
      <h3 class="text-lg font-semibold mb-2 text-center">Preview Mapping</h3>
      <p class="text-base-content/70 mb-4 text-center">
        Review the captured input ranges before saving.
      </p>

      <div class="space-y-2 mb-6 max-h-64 overflow-y-auto">
        <div
          :for={{notch, idx} <- Enum.with_index(@notch_data)}
          class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
        >
          <div class="flex items-center gap-3">
            <span class={[
              "w-6 h-6 rounded-full flex items-center justify-center text-xs font-medium",
              notch_type_badge_class(notch.type)
            ]}>
              {notch_type_abbrev(notch.type)}
            </span>
            <span class="font-medium">{notch.description}</span>
          </div>
          <button
            phx-click="go_to_notch"
            phx-value-index={idx}
            phx-target={@myself}
            class="font-mono text-sm hover:text-primary transition-colors"
          >
            {format_calibrated(notch.range.min)} – {format_calibrated(notch.range.max)}
          </button>
        </div>
      </div>

      <div class="flex justify-between gap-4 pt-4 border-t border-base-300">
        <button
          phx-click="go_to_notch"
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

  defp get_notch_instruction(%{type: :gate, description: desc}) do
    "Wiggle the lever within the #{desc} position to capture its range."
  end

  defp get_notch_instruction(%{type: :linear, description: desc}) do
    "Move the lever through the full #{desc} range, from minimum to maximum."
  end

  defp get_notch_instruction(%{description: desc}) do
    "Move the lever through the #{desc} range to capture min and max positions."
  end

  defp format_calibrated(nil), do: "—"
  defp format_calibrated(value) when is_integer(value), do: Integer.to_string(value)

  defp format_calibrated(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 0)

  defp notch_type_badge_class(:gate), do: "bg-warning/20 text-warning"
  defp notch_type_badge_class(:linear), do: "bg-info/20 text-info"
  defp notch_type_badge_class(_), do: "bg-base-300 text-base-content/70"

  defp notch_type_abbrev(:gate), do: "G"
  defp notch_type_abbrev(:linear), do: "L"
  defp notch_type_abbrev(_), do: "?"

  defp format_error({:error, reason}) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error({:error, reason}), do: inspect(reason)
  defp format_error(_), do: "Unknown error"
end
