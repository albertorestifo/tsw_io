defmodule TswIo.Train.Calibration.NotchMappingSession do
  @moduledoc """
  Manages a guided session for mapping physical lever positions to notch input ranges.

  This session helps users define input ranges for each notch by tracking the
  min/max values as they move the physical lever.

  ## Workflow

  1. Start session with lever config and bound input info
  2. For each notch:
     - User positions lever at the notch (samples NOT collected yet)
     - User clicks "Start Capturing" to begin sample collection
     - Gate: User wiggles the lever within the detent position
     - Linear: User sweeps the lever through the full notch range
     - System tracks min/max of all samples collected
     - User confirms to capture the range
  3. Preview all mapped ranges
  4. Save notch input ranges to database

  ## Value Types

  During mapping, we work with **calibrated values** (integers from 0 to total_travel).
  These provide full hardware precision. When saving, values are normalized to 0.0-1.0
  for storage in the database.

  ## Events

  Broadcasts events to `train:notch_mapping:{lever_config_id}`:

  - `{:session_started, public_state}` - Session began
  - `{:step_changed, public_state}` - Advanced to next step
  - `{:sample_updated, public_state}` - Current value/range updated
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
  @min_sample_count 10

  defmodule State do
    @moduledoc false

    @type step ::
            :ready
            | {:mapping_notch, non_neg_integer()}
            | :preview
            | :saving
            | :complete

    @type notch_range :: %{min: integer(), max: integer()} | nil

    @type t :: %__MODULE__{
            lever_config_id: integer(),
            lever_config: LeverConfig.t(),
            port: String.t(),
            pin: integer(),
            calibration: Calibration.t(),
            total_travel: integer(),
            notches: [map()],
            current_step: step(),
            is_capturing: boolean(),
            captured_ranges: [notch_range()],
            current_samples: [integer()],
            current_value: integer() | nil,
            current_min: integer() | nil,
            current_max: integer() | nil,
            result: {:ok, LeverConfig.t()} | {:error, term()} | nil
          }

    defstruct [
      :lever_config_id,
      :lever_config,
      :port,
      :pin,
      :calibration,
      :total_travel,
      notches: [],
      current_step: :ready,
      is_capturing: false,
      captured_ranges: [],
      current_samples: [],
      current_value: nil,
      current_min: nil,
      current_max: nil,
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
  Start the mapping process (move from :ready to first notch).
  """
  @spec start_mapping(pid()) :: :ok | {:error, term()}
  def start_mapping(pid) do
    GenServer.call(pid, :start_mapping)
  end

  @doc """
  Capture the current min/max range for the current notch.
  """
  @spec capture_range(pid()) :: :ok | {:error, term()}
  def capture_range(pid) do
    GenServer.call(pid, :capture_range)
  end

  @doc """
  Clear current samples and start fresh for the current notch.
  """
  @spec reset_samples(pid()) :: :ok | {:error, term()}
  def reset_samples(pid) do
    GenServer.call(pid, :reset_samples)
  end

  @doc """
  Begin capturing samples for the current notch.
  Call this after the user has positioned the lever.
  """
  @spec start_capturing(pid()) :: :ok | {:error, term()}
  def start_capturing(pid) do
    GenServer.call(pid, :start_capturing)
  end

  @doc """
  Stop capturing samples (returns to positioning state).
  """
  @spec stop_capturing(pid()) :: :ok | {:error, term()}
  def stop_capturing(pid) do
    GenServer.call(pid, :stop_capturing)
  end

  @doc """
  Skip to a specific notch (for editing).
  """
  @spec go_to_notch(pid(), non_neg_integer()) :: :ok | {:error, term()}
  def go_to_notch(pid, notch_index) do
    GenServer.call(pid, {:go_to_notch, notch_index})
  end

  @doc """
  Move to preview step.
  """
  @spec go_to_preview(pid()) :: :ok | {:error, term()}
  def go_to_preview(pid) do
    GenServer.call(pid, :go_to_preview)
  end

  @doc """
  Save the mapped notch ranges.
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

  # Keep old API for compatibility
  @doc false
  def capture_boundary(pid), do: capture_range(pid)

  @doc false
  def go_to_boundary(pid, idx), do: go_to_notch(pid, idx)

  # Server callbacks

  @impl true
  def init(opts) do
    lever_config = Keyword.fetch!(opts, :lever_config)
    port = Keyword.fetch!(opts, :port)
    pin = Keyword.fetch!(opts, :pin)
    calibration = Keyword.fetch!(opts, :calibration)

    total_travel = Calculator.total_travel(calibration)

    notches =
      lever_config.notches
      |> Enum.sort_by(& &1.index)
      |> Enum.map(fn notch ->
        %{
          id: notch.id,
          index: notch.index,
          type: notch.type,
          description: notch.description || "Notch #{notch.index}"
        }
      end)

    Logger.debug(
      "NotchMappingSession starting for lever_config #{lever_config.id}, " <>
        "#{length(notches)} notches, total_travel #{total_travel}"
    )

    # Subscribe to input values for this port
    Hardware.subscribe_input_values(port)

    state = %State{
      lever_config_id: lever_config.id,
      lever_config: lever_config,
      port: port,
      pin: pin,
      calibration: calibration,
      total_travel: total_travel,
      notches: notches,
      captured_ranges: List.duplicate(nil, length(notches))
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
    new_state = %{
      state
      | current_step: {:mapping_notch, 0},
        is_capturing: false,
        current_samples: [],
        current_min: nil,
        current_max: nil
    }

    broadcast_event(new_state, :step_changed)
    {:reply, :ok, new_state}
  end

  def handle_call(:start_mapping, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_call(:capture_range, _from, %State{current_step: {:mapping_notch, idx}} = state) do
    case validate_capture(state) do
      :ok ->
        range = %{min: state.current_min, max: state.current_max}
        new_ranges = List.replace_at(state.captured_ranges, idx, range)

        next_step =
          if idx + 1 >= length(state.notches) do
            :preview
          else
            {:mapping_notch, idx + 1}
          end

        new_state = %{
          state
          | captured_ranges: new_ranges,
            current_step: next_step,
            is_capturing: false,
            current_samples: [],
            current_min: nil,
            current_max: nil
        }

        broadcast_event(new_state, :step_changed)
        {:reply, :ok, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:capture_range, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  # Alias for compatibility
  def handle_call(:capture_boundary, from, state) do
    handle_call(:capture_range, from, state)
  end

  @impl true
  def handle_call(:reset_samples, _from, %State{current_step: {:mapping_notch, _}} = state) do
    new_state = %{
      state
      | is_capturing: false,
        current_samples: [],
        current_min: nil,
        current_max: nil
    }

    broadcast_event(new_state, :sample_updated)
    {:reply, :ok, new_state}
  end

  def handle_call(:reset_samples, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_call(:start_capturing, _from, %State{current_step: {:mapping_notch, _}} = state) do
    new_state = %{
      state
      | is_capturing: true,
        current_samples: [],
        current_min: nil,
        current_max: nil
    }

    broadcast_event(new_state, :capture_started)
    {:reply, :ok, new_state}
  end

  def handle_call(:start_capturing, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_call(:stop_capturing, _from, %State{current_step: {:mapping_notch, _}} = state) do
    new_state = %{
      state
      | is_capturing: false,
        current_samples: [],
        current_min: nil,
        current_max: nil
    }

    broadcast_event(new_state, :capture_stopped)
    {:reply, :ok, new_state}
  end

  def handle_call(:stop_capturing, _from, %State{} = state) do
    {:reply, {:error, :invalid_step}, state}
  end

  @impl true
  def handle_call({:go_to_notch, idx}, _from, %State{} = state)
      when idx >= 0 and idx < length(state.notches) do
    new_state = %{
      state
      | current_step: {:mapping_notch, idx},
        is_capturing: false,
        current_samples: [],
        current_min: nil,
        current_max: nil
    }

    broadcast_event(new_state, :step_changed)
    {:reply, :ok, new_state}
  end

  def handle_call({:go_to_notch, _idx}, _from, %State{} = state) do
    {:reply, {:error, :invalid_notch_index}, state}
  end

  # Alias for compatibility
  def handle_call({:go_to_boundary, idx}, from, state) do
    handle_call({:go_to_notch, idx}, from, state)
  end

  @impl true
  def handle_call(:go_to_preview, _from, %State{} = state) do
    if all_ranges_captured?(state) do
      new_state = %{state | current_step: :preview}
      broadcast_event(new_state, :step_changed)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :incomplete_ranges}, state}
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
      {:mapping_notch, _idx} ->
        # Convert to calibrated value (integer 0 to total_travel)
        calibrated = Calculator.normalize(raw_value, state.calibration)

        # Always update current_value so user can see lever position during positioning
        # Only collect samples and update min/max when actively capturing
        new_state =
          if state.is_capturing do
            new_samples = [calibrated | state.current_samples]

            new_min =
              case state.current_min do
                nil -> calibrated
                current -> min(current, calibrated)
              end

            new_max =
              case state.current_max do
                nil -> calibrated
                current -> max(current, calibrated)
              end

            %{
              state
              | current_samples: new_samples,
                current_value: calibrated,
                current_min: new_min,
                current_max: new_max
            }
          else
            # Positioning mode: only update current value for display
            %{state | current_value: calibrated}
          end

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

  defp validate_capture(%State{current_samples: samples, current_min: min, current_max: max}) do
    cond do
      length(samples) < @min_sample_count ->
        {:error, :not_enough_samples}

      is_nil(min) or is_nil(max) ->
        {:error, :no_range_detected}

      min == max ->
        {:error, :no_range_detected}

      true ->
        :ok
    end
  end

  defp all_ranges_captured?(%State{captured_ranges: ranges}) do
    Enum.all?(ranges, &(&1 != nil))
  end

  defp save_notch_ranges(%State{} = state) do
    # Convert calibrated values to normalized 0.0-1.0
    notch_updates =
      state.notches
      |> Enum.with_index()
      |> Enum.map(fn {notch, idx} ->
        range = Enum.at(state.captured_ranges, idx)

        %{
          id: notch.id,
          input_min: calibrated_to_normalized(range.min, state.total_travel),
          input_max: calibrated_to_normalized(range.max, state.total_travel)
        }
      end)

    Train.update_notch_input_ranges(state.lever_config_id, notch_updates)
  end

  defp calibrated_to_normalized(calibrated, total_travel) when total_travel > 0 do
    Float.round(calibrated / total_travel, 4)
  end

  defp calibrated_to_normalized(_calibrated, _total_travel), do: 0.0

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
    current_notch_idx = current_notch_index(state.current_step)

    current_notch =
      if current_notch_idx do
        Enum.at(state.notches, current_notch_idx)
      else
        nil
      end

    %{
      lever_config_id: state.lever_config_id,
      notch_count: length(state.notches),
      notches: state.notches,
      total_travel: state.total_travel,
      current_step: state.current_step,
      current_notch_index: current_notch_idx,
      current_notch: current_notch,
      is_capturing: state.is_capturing,
      captured_ranges: state.captured_ranges,
      current_value: state.current_value,
      current_min: state.current_min,
      current_max: state.current_max,
      sample_count: length(state.current_samples),
      can_capture: can_capture?(state),
      all_captured: all_ranges_captured?(state),
      result: state.result,
      # Legacy fields for compatibility
      boundary_count: length(state.notches) + 1,
      current_boundary_index: current_notch_idx,
      captured_boundaries: state.captured_ranges,
      notch_descriptions: Enum.map(state.notches, & &1.description),
      is_stable: length(state.current_samples) >= @min_sample_count
    }
  end

  defp current_notch_index({:mapping_notch, idx}), do: idx
  defp current_notch_index(_), do: nil

  defp can_capture?(%State{current_step: {:mapping_notch, _}} = state) do
    length(state.current_samples) >= @min_sample_count and
      state.current_min != nil and
      state.current_max != nil and
      state.current_min != state.current_max
  end

  defp can_capture?(_state), do: false
end
