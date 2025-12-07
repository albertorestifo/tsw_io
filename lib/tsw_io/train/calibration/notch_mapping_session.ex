defmodule TswIo.Train.Calibration.NotchMappingSession do
  @moduledoc """
  Manages a guided session for mapping physical lever positions to notch boundaries.

  This session helps users associate normalized input values (0.0-1.0) with
  notch boundaries by guiding them through each boundary point step by step.

  ## Workflow

  1. Start session with lever config and bound input info
  2. For each boundary (n+1 for n notches):
     - User moves physical lever to the desired position
     - System collects samples for stability
     - User confirms to capture the boundary value
  3. Preview all mapped ranges
  4. Save notch input ranges to database

  ## Events

  Broadcasts events to `train:notch_mapping:{lever_config_id}`:

  - `{:session_started, public_state}` - Session began
  - `{:step_changed, public_state}` - Advanced to next step
  - `{:sample_updated, public_state}` - Current value updated
  - `{:mapping_result, {:ok, lever_config}}` - Success
  - `{:mapping_result, {:error, reason}}` - Failure
  """

  use GenServer

  alias TswIo.Hardware
  alias TswIo.Hardware.Calibration.Calculator
  alias TswIo.Hardware.Input.Calibration
  alias TswIo.Train
  alias TswIo.Train.LeverConfig

  require Logger

  @mapping_topic "train:notch_mapping"
  @min_sample_count 5
  @stability_threshold 0.02

  defmodule State do
    @moduledoc false

    @type step ::
            :ready
            | {:mapping_boundary, non_neg_integer()}
            | :preview
            | :saving
            | :complete

    @type t :: %__MODULE__{
            lever_config_id: integer(),
            lever_config: LeverConfig.t(),
            port: String.t(),
            pin: integer(),
            calibration: Calibration.t(),
            notch_count: non_neg_integer(),
            notch_descriptions: [String.t()],
            current_step: step(),
            boundary_count: non_neg_integer(),
            captured_boundaries: [float()],
            current_samples: [float()],
            current_value: float() | nil,
            result: {:ok, LeverConfig.t()} | {:error, term()} | nil
          }

    defstruct [
      :lever_config_id,
      :lever_config,
      :port,
      :pin,
      :calibration,
      :notch_count,
      notch_descriptions: [],
      current_step: :ready,
      boundary_count: 0,
      captured_boundaries: [],
      current_samples: [],
      current_value: nil,
      result: nil
    ]
  end

  # Client API

  @doc """
  Start a notch mapping session.

  ## Options

    * `:lever_config` - Required. The lever config with preloaded notches.
    * `:port` - Required. The serial port of the bound device.
    * `:pin` - Required. The pin number of the bound input.
    * `:calibration` - Required. The input's calibration data.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    lever_config = Keyword.fetch!(opts, :lever_config)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(lever_config.id))
  end

  @doc """
  Get the registry name for a session.
  """
  @spec whereis(integer()) :: pid() | nil
  def whereis(lever_config_id) do
    case Registry.lookup(TswIo.Registry, {__MODULE__, lever_config_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Get the current state of the mapping session.
  """
  @spec get_state(pid()) :: State.t()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Get the public state suitable for UI display.
  """
  @spec get_public_state(pid()) :: map()
  def get_public_state(pid) do
    GenServer.call(pid, :get_public_state)
  end

  @doc """
  Start the mapping process (move from :ready to first boundary).
  """
  @spec start_mapping(pid()) :: :ok | {:error, term()}
  def start_mapping(pid) do
    GenServer.call(pid, :start_mapping)
  end

  @doc """
  Capture the current value as the boundary position.
  """
  @spec capture_boundary(pid()) :: :ok | {:error, term()}
  def capture_boundary(pid) do
    GenServer.call(pid, :capture_boundary)
  end

  @doc """
  Skip to a specific boundary (for editing).
  """
  @spec go_to_boundary(pid(), non_neg_integer()) :: :ok | {:error, term()}
  def go_to_boundary(pid, boundary_index) do
    GenServer.call(pid, {:go_to_boundary, boundary_index})
  end

  @doc """
  Move to preview step.
  """
  @spec go_to_preview(pid()) :: :ok | {:error, term()}
  def go_to_preview(pid) do
    GenServer.call(pid, :go_to_preview)
  end

  @doc """
  Save the mapped notch boundaries.
  """
  @spec save_mapping(pid()) :: :ok | {:error, term()}
  def save_mapping(pid) do
    GenServer.call(pid, :save_mapping)
  end

  @doc """
  Cancel the mapping session.
  """
  @spec cancel(pid()) :: :ok
  def cancel(pid) do
    GenServer.cast(pid, :cancel)
  end

  @doc """
  Subscribe to mapping events for a specific lever config.
  """
  @spec subscribe(integer()) :: :ok | {:error, term()}
  def subscribe(lever_config_id) do
    Phoenix.PubSub.subscribe(TswIo.PubSub, "#{@mapping_topic}:#{lever_config_id}")
  end

  # Server callbacks

  @impl true
  def init(opts) do
    lever_config = Keyword.fetch!(opts, :lever_config)
    port = Keyword.fetch!(opts, :port)
    pin = Keyword.fetch!(opts, :pin)
    calibration = Keyword.fetch!(opts, :calibration)

    notch_count = length(lever_config.notches)
    boundary_count = notch_count + 1

    notch_descriptions =
      lever_config.notches
      |> Enum.sort_by(& &1.index)
      |> Enum.map(fn notch ->
        notch.description || "Notch #{notch.index}"
      end)

    Logger.debug(
      "NotchMappingSession starting for lever_config #{lever_config.id}, " <>
        "#{notch_count} notches, #{boundary_count} boundaries"
    )

    # Subscribe to input values for this port
    Hardware.subscribe_input_values(port)

    state = %State{
      lever_config_id: lever_config.id,
      lever_config: lever_config,
      port: port,
      pin: pin,
      calibration: calibration,
      notch_count: notch_count,
      notch_descriptions: notch_descriptions,
      boundary_count: boundary_count,
      captured_boundaries: List.duplicate(nil, boundary_count)
    }

    broadcast_event(state, :session_started)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_public_state, _from, %State{} = state) do
    {:reply, build_public_state(state), state}
  end

  @impl true
  def handle_call(:start_mapping, _from, %State{current_step: :ready} = state) do
    new_state = %{state | current_step: {:mapping_boundary, 0}, current_samples: []}
    broadcast_event(new_state, :step_changed)
    {:reply, :ok, new_state}
  end

  def handle_call(:start_mapping, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_call(
        :capture_boundary,
        _from,
        %State{current_step: {:mapping_boundary, idx}} = state
      ) do
    case validate_capture(state) do
      :ok ->
        # Use the average of recent samples for stability
        value = calculate_stable_value(state.current_samples)

        new_boundaries = List.replace_at(state.captured_boundaries, idx, value)

        next_step =
          if idx + 1 >= state.boundary_count do
            :preview
          else
            {:mapping_boundary, idx + 1}
          end

        new_state = %{
          state
          | captured_boundaries: new_boundaries,
            current_step: next_step,
            current_samples: []
        }

        broadcast_event(new_state, :step_changed)
        {:reply, :ok, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:capture_boundary, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_call({:go_to_boundary, idx}, _from, %State{} = state)
      when idx >= 0 and idx < state.boundary_count do
    new_state = %{state | current_step: {:mapping_boundary, idx}, current_samples: []}
    broadcast_event(new_state, :step_changed)
    {:reply, :ok, new_state}
  end

  def handle_call({:go_to_boundary, _idx}, _from, %State{} = state) do
    {:reply, {:error, :invalid_boundary_index}, state}
  end

  @impl true
  def handle_call(:go_to_preview, _from, %State{} = state) do
    if all_boundaries_captured?(state) do
      new_state = %{state | current_step: :preview}
      broadcast_event(new_state, :step_changed)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :incomplete_boundaries}, state}
    end
  end

  @impl true
  def handle_call(:save_mapping, _from, %State{current_step: :preview} = state) do
    new_state = %{state | current_step: :saving}
    broadcast_event(new_state, :step_changed)

    case save_notch_ranges(state) do
      {:ok, updated_config} ->
        final_state = %{new_state | current_step: :complete, result: {:ok, updated_config}}
        broadcast_result(final_state, {:ok, updated_config})
        {:reply, :ok, final_state}

      {:error, _reason} = error ->
        final_state = %{new_state | current_step: :complete, result: error}
        broadcast_result(final_state, error)
        {:reply, error, final_state}
    end
  end

  def handle_call(:save_mapping, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_cast(:cancel, %State{} = state) do
    Logger.info("NotchMappingSession cancelled for lever_config #{state.lever_config_id}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:input_value_updated, _port, pin, raw_value}, %State{pin: pin} = state) do
    case state.current_step do
      {:mapping_boundary, _idx} ->
        normalized = normalize_value(raw_value, state.calibration)
        new_samples = [normalized | Enum.take(state.current_samples, @min_sample_count - 1)]

        new_state = %{
          state
          | current_samples: new_samples,
            current_value: normalized
        }

        broadcast_event(new_state, :sample_updated)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:input_value_updated, _port, _other_pin, _value}, %State{} = state) do
    {:noreply, state}
  end

  # Private helpers

  defp via_tuple(lever_config_id) do
    {:via, Registry, {TswIo.Registry, {__MODULE__, lever_config_id}}}
  end

  defp normalize_value(raw_value, %Calibration{} = calibration) do
    normalized = Calculator.normalize(raw_value, calibration)
    total = Calculator.total_travel(calibration)

    if total > 0 do
      Float.round(normalized / total, 2)
    else
      0.0
    end
  end

  defp validate_capture(%State{current_samples: samples}) do
    if length(samples) >= @min_sample_count and is_stable?(samples) do
      :ok
    else
      {:error, :unstable_value}
    end
  end

  defp is_stable?(samples) when length(samples) < @min_sample_count, do: false

  defp is_stable?(samples) do
    min_val = Enum.min(samples)
    max_val = Enum.max(samples)
    max_val - min_val <= @stability_threshold
  end

  defp calculate_stable_value(samples) do
    samples
    |> Enum.take(@min_sample_count)
    |> then(&(Enum.sum(&1) / length(&1)))
    |> Float.round(2)
  end

  defp all_boundaries_captured?(%State{captured_boundaries: boundaries}) do
    Enum.all?(boundaries, &(&1 != nil))
  end

  defp save_notch_ranges(%State{} = state) do
    # Convert boundaries to notch input ranges
    # boundaries = [b0, b1, b2, ...] where:
    # notch 0: input_min = b0, input_max = b1
    # notch 1: input_min = b1, input_max = b2
    # etc.

    sorted_boundaries = Enum.sort(state.captured_boundaries)

    notch_updates =
      state.lever_config.notches
      |> Enum.sort_by(& &1.index)
      |> Enum.with_index()
      |> Enum.map(fn {notch, idx} ->
        %{
          id: notch.id,
          input_min: Enum.at(sorted_boundaries, idx),
          input_max: Enum.at(sorted_boundaries, idx + 1)
        }
      end)

    Train.update_notch_input_ranges(state.lever_config_id, notch_updates)
  end

  defp broadcast_event(%State{} = state, event) do
    Phoenix.PubSub.broadcast(
      TswIo.PubSub,
      "#{@mapping_topic}:#{state.lever_config_id}",
      {event, build_public_state(state)}
    )
  end

  defp broadcast_result(%State{} = state, result) do
    Phoenix.PubSub.broadcast(
      TswIo.PubSub,
      "#{@mapping_topic}:#{state.lever_config_id}",
      {:mapping_result, result}
    )
  end

  defp build_public_state(%State{} = state) do
    %{
      lever_config_id: state.lever_config_id,
      notch_count: state.notch_count,
      notch_descriptions: state.notch_descriptions,
      boundary_count: state.boundary_count,
      current_step: state.current_step,
      current_boundary_index: current_boundary_index(state.current_step),
      captured_boundaries: state.captured_boundaries,
      current_value: state.current_value,
      sample_count: length(state.current_samples),
      is_stable: is_stable?(state.current_samples),
      can_capture: can_capture?(state),
      all_captured: all_boundaries_captured?(state),
      result: state.result
    }
  end

  defp current_boundary_index({:mapping_boundary, idx}), do: idx
  defp current_boundary_index(_), do: nil

  defp can_capture?(%State{current_step: {:mapping_boundary, _}} = state) do
    length(state.current_samples) >= @min_sample_count and is_stable?(state.current_samples)
  end

  defp can_capture?(_state), do: false
end
