defmodule TswIoWeb.CalibrationWizard do
  @moduledoc """
  LiveComponent for calibrating an input through a step-by-step wizard.

  The wizard guides the user through:
  1. Collecting minimum samples - Hold input at minimum position
  2. Sweeping - Move through full range
  3. Collecting maximum samples - Hold input at maximum position
  4. Analysis and saving

  ## Usage

      <.live_component
        module={TswIoWeb.CalibrationWizard}
        id="calibration-wizard"
        input={@calibrating_input}
        port={@port}
      />
  """

  use TswIoWeb, :live_component

  alias TswIo.Hardware
  alias TswIo.Hardware.Calibration.Session

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:session_pid, nil)
     |> assign(:session_state, nil)}
  end

  @impl true
  def update(%{input: input, port: port} = assigns, socket) do
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
      Session.subscribe(input.id)

      case Hardware.start_calibration_session(input, port) do
        {:ok, pid} ->
          state = Session.get_public_state(pid)

          {:ok,
           socket
           |> assign(:session_pid, pid)
           |> assign(:session_state, state)}

        {:error, reason} ->
          send(self(), {:calibration_error, reason})
          {:ok, socket}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("advance_step", _params, socket) do
    case Session.advance_step(socket.assigns.session_pid) do
      :ok ->
        {:noreply, socket}

      {:error, :insufficient_samples} ->
        {:noreply, put_flash(socket, :error, "Need more samples. Keep the input steady.")}

      {:error, :insufficient_sweep_samples} ->
        {:noreply, put_flash(socket, :error, "Need more movement. Sweep through the full range.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot advance: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    if socket.assigns.session_pid do
      Session.cancel(socket.assigns.session_pid)
    end

    send(self(), :calibration_cancelled)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/50" phx-click="cancel" phx-target={@myself} />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-lg mx-4 p-6">
        <.wizard_header input={@input} target={@myself} />

        <.loading_state :if={is_nil(@session_state)} />

        <div :if={@session_state}>
          <.step_indicator current_step={@session_state.current_step} />

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

  attr :input, :map, required: true
  attr :target, :any, required: true, doc: "The LiveComponent to target for events"

  defp wizard_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="text-xl font-semibold">Calibrate Input</h2>
        <p class="text-sm text-base-content/70">Pin {@input.pin}</p>
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
      <p class="mt-4 text-base-content/70">Starting calibration session...</p>
    </div>
    """
  end

  attr :current_step, :atom, required: true

  defp step_indicator(assigns) do
    steps = [:collecting_min, :sweeping, :collecting_max, :analyzing]
    current_index = Enum.find_index(steps, &(&1 == assigns.current_step)) || 0

    assigns =
      assigns
      |> assign(:steps, steps)
      |> assign(:current_index, current_index)

    ~H"""
    <div class="flex items-center justify-center gap-2 mb-8">
      <div :for={{step, index} <- Enum.with_index(@steps)} class="flex items-center">
        <div class={[
          "w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium transition-colors",
          step_class(index, @current_index)
        ]}>
          <.icon :if={index < @current_index} name="hero-check" class="w-4 h-4" />
          <span :if={index >= @current_index}>{index + 1}</span>
        </div>
        <div
          :if={index < length(@steps) - 1}
          class={[
            "w-8 h-0.5 mx-1",
            if(index < @current_index, do: "bg-primary", else: "bg-base-300")
          ]}
        />
      </div>
    </div>
    """
  end

  defp step_class(index, current_index) when index < current_index do
    "bg-primary text-primary-content"
  end

  defp step_class(index, current_index) when index == current_index do
    "bg-primary text-primary-content ring-4 ring-primary/30"
  end

  defp step_class(_index, _current_index) do
    "bg-base-300 text-base-content/50"
  end

  attr :session_state, :map, required: true
  attr :myself, :any, required: true

  defp step_content(assigns) do
    ~H"""
    <div class="space-y-6">
      <.collecting_min_step
        :if={@session_state.current_step == :collecting_min}
        state={@session_state}
      />
      <.sweeping_step :if={@session_state.current_step == :sweeping} state={@session_state} />
      <.collecting_max_step
        :if={@session_state.current_step == :collecting_max}
        state={@session_state}
      />
      <.analyzing_step :if={@session_state.current_step == :analyzing} />
      <.complete_step :if={@session_state.current_step == :complete} state={@session_state} />

      <.action_buttons
        :if={@session_state.current_step not in [:analyzing, :complete]}
        session_state={@session_state}
        myself={@myself}
      />
    </div>
    """
  end

  attr :state, :map, required: true

  defp collecting_min_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-info/10 flex items-center justify-center">
        <.icon name="hero-arrow-down-circle" class="w-8 h-8 text-info" />
      </div>
      <h3 class="text-lg font-semibold mb-2">Set Minimum Position</h3>
      <p class="text-base-content/70 mb-4">
        Move the input to its <strong>minimum</strong> position and hold it steady.
      </p>

      <.sample_counter
        count={@state.min_sample_count}
        unique={@state.min_unique_count}
        min_required={10}
        min_unique={3}
      />
    </div>
    """
  end

  attr :state, :map, required: true

  defp sweeping_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-warning/10 flex items-center justify-center">
        <.icon name="hero-arrows-right-left" class="w-8 h-8 text-warning" />
      </div>
      <h3 class="text-lg font-semibold mb-2">Sweep Through Range</h3>
      <p class="text-base-content/70 mb-4">
        Slowly move the input from <strong>minimum</strong> to <strong>maximum</strong> position.
      </p>

      <div class="bg-base-200 rounded-lg p-4">
        <div class="text-2xl font-bold text-primary">{@state.sweep_sample_count}</div>
        <div class="text-sm text-base-content/70">samples collected</div>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true

  defp collecting_max_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-success/10 flex items-center justify-center">
        <.icon name="hero-arrow-up-circle" class="w-8 h-8 text-success" />
      </div>
      <h3 class="text-lg font-semibold mb-2">Set Maximum Position</h3>
      <p class="text-base-content/70 mb-4">
        Move the input to its <strong>maximum</strong> position and hold it steady.
      </p>

      <.sample_counter
        count={@state.max_sample_count}
        unique={@state.max_unique_count}
        min_required={10}
        min_unique={3}
      />
    </div>
    """
  end

  defp analyzing_step(assigns) do
    ~H"""
    <div class="text-center py-8">
      <span class="loading loading-spinner loading-lg text-primary"></span>
      <p class="mt-4 text-base-content/70">Analyzing calibration data...</p>
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
        <h3 class="text-lg font-semibold">Calibration Complete!</h3>
        <p class="text-base-content/70">
          The input has been calibrated successfully.
        </p>
      </div>

      <div :if={match?({:error, _}, @state.result)} class="space-y-4">
        <div class="w-16 h-16 mx-auto rounded-full bg-error/10 flex items-center justify-center">
          <.icon name="hero-exclamation-circle" class="w-8 h-8 text-error" />
        </div>
        <h3 class="text-lg font-semibold">Calibration Failed</h3>
        <p class="text-base-content/70">
          {format_error(@state.result)}
        </p>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :unique, :integer, required: true
  attr :min_required, :integer, required: true
  attr :min_unique, :integer, required: true

  defp sample_counter(assigns) do
    count_ok = assigns.count >= assigns.min_required
    unique_ok = assigns.unique >= assigns.min_unique

    assigns =
      assigns
      |> assign(:count_ok, count_ok)
      |> assign(:unique_ok, unique_ok)

    ~H"""
    <div class="bg-base-200 rounded-lg p-4 space-y-2">
      <div class="flex items-center justify-between">
        <span class="text-sm text-base-content/70">Samples</span>
        <span class={[
          "font-mono font-bold",
          if(@count_ok, do: "text-success", else: "text-base-content")
        ]}>
          {@count} / {@min_required}
          <.icon :if={@count_ok} name="hero-check" class="w-4 h-4 inline ml-1" />
        </span>
      </div>
      <div class="flex items-center justify-between">
        <span class="text-sm text-base-content/70">Unique values</span>
        <span class={[
          "font-mono font-bold",
          if(@unique_ok, do: "text-success", else: "text-base-content")
        ]}>
          {@unique} / {@min_unique}
          <.icon :if={@unique_ok} name="hero-check" class="w-4 h-4 inline ml-1" />
        </span>
      </div>
    </div>
    """
  end

  attr :session_state, :map, required: true
  attr :myself, :any, required: true

  defp action_buttons(assigns) do
    ~H"""
    <div class="flex justify-between gap-4 pt-4 border-t border-base-300">
      <button
        phx-click="cancel"
        phx-target={@myself}
        class="btn btn-ghost"
      >
        Cancel
      </button>
      <button
        phx-click="advance_step"
        phx-target={@myself}
        disabled={!@session_state.can_advance}
        class="btn btn-primary"
      >
        {advance_button_text(@session_state.current_step)}
        <.icon name="hero-arrow-right" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  defp advance_button_text(:collecting_min), do: "Next: Sweep"
  defp advance_button_text(:sweeping), do: "Next: Set Max"
  defp advance_button_text(:collecting_max), do: "Finish"
  defp advance_button_text(_), do: "Continue"

  defp format_error({:error, reason}) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error({:error, reason}), do: inspect(reason)
  defp format_error(_), do: "Unknown error"
end
