defmodule TswIo.Hardware.Calibration.Analyzer do
  @moduledoc """
  Analyzes calibration sweep data to detect input characteristics.

  The analyzer detects:
  - `inverted` - input values decrease as physical position increases
  - `rollover` - values wrap from max (1023) to 0 during sweep
  """

  alias TswIo.Hardware.Calibration.Analyzer.Analysis

  @doc """
  Analyzes sweep samples to detect input characteristics.

  Returns an Analysis struct with boolean flags for each characteristic.

  ## Examples

      # Normal input (increasing values)
      iex> analyze_sweep([10, 50, 100, 150], 1023)
      {:ok, %Analysis{inverted: false, rollover: false}}

      # Inverted input (decreasing values)
      iex> analyze_sweep([150, 100, 50, 10], 1023)
      {:ok, %Analysis{inverted: true, rollover: false}}

      # Rollover detected
      iex> analyze_sweep([1020, 1022, 1023, 0, 5, 10], 1023)
      {:ok, %Analysis{inverted: false, rollover: true}}
  """
  @spec analyze_sweep([integer()], integer()) :: {:ok, Analysis.t()}
  def analyze_sweep(sweep_samples, _max_hardware_value) when length(sweep_samples) < 2 do
    {:ok, %Analysis{inverted: false, rollover: false}}
  end

  def analyze_sweep(sweep_samples, max_hardware_value) do
    {:ok,
     %Analysis{
       inverted: inverted?(sweep_samples),
       rollover: rollover?(sweep_samples, max_hardware_value)
     }}
  end

  @doc """
  Calculates the logical minimum value from samples.

  For inverted inputs, returns the inverted value (max_hardware - median)
  so that Calculator can apply the same inversion to raw values.
  """
  @spec calculate_min([integer()], Analysis.t(), integer()) :: integer()
  def calculate_min(min_samples, analysis, max_hardware_value \\ 1023)

  def calculate_min(min_samples, %Analysis{inverted: true}, max_hardware_value) do
    max_hardware_value - median(min_samples)
  end

  def calculate_min(min_samples, %Analysis{inverted: false}, _max_hardware_value) do
    median(min_samples)
  end

  @doc """
  Calculates the logical maximum value from samples.

  For inverted inputs, returns the inverted value.
  For rollover inputs, accounts for the wrap-around.
  """
  @spec calculate_max([integer()], [integer()], Analysis.t(), integer()) :: integer()
  def calculate_max(max_samples, min_samples, %Analysis{} = analysis, max_hardware_value) do
    max_median = median(max_samples)
    min_median = median(min_samples)

    {effective_min, effective_max} =
      if analysis.inverted do
        {max_hardware_value - min_median, max_hardware_value - max_median}
      else
        {min_median, max_median}
      end

    if analysis.rollover do
      effective_max + (max_hardware_value - effective_min + 1)
    else
      effective_max
    end
  end

  # Private functions

  defp inverted?(sweep_samples) do
    deltas =
      sweep_samples
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    median_delta = median(deltas)
    median_delta < 0
  end

  defp rollover?(sweep_samples, max_hardware_value) do
    deltas =
      sweep_samples
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> abs(b - a) end)

    case deltas do
      [] ->
        false

      deltas ->
        median_delta = median(deltas)
        max_delta = Enum.max(deltas)

        # Rollover detected if:
        # 1. Max delta is significantly larger than median (3x)
        # 2. Max delta is close to hardware max (80%)
        threshold = max(median_delta * 3, 10)
        max_delta > threshold and max_delta > max_hardware_value * 0.8
    end
  end

  defp median([]), do: 0

  defp median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      div(Enum.at(sorted, mid - 1) + Enum.at(sorted, mid), 2)
    else
      Enum.at(sorted, mid)
    end
  end
end
