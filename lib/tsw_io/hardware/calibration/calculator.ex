defmodule TswIo.Hardware.Calibration.Calculator do
  @moduledoc """
  Calculates normalized input values using calibration data.

  The normalized value ranges from 0 (at min) to total_travel (at max).
  Handles inversion and rollover automatically.
  """

  alias TswIo.Hardware.Input.Calibration

  @doc """
  Converts a raw input value to a normalized value.

  The normalized value ranges from 0 (at min) to total_travel (at max).
  Handles inversion and rollover automatically.

  ## Examples

      iex> calibration = %Calibration{min_value: 10, max_value: 150, is_inverted: false, has_rollover: false, max_hardware_value: 1023}
      iex> normalize(10, calibration)
      0

      iex> normalize(80, calibration)
      70

      iex> normalize(150, calibration)
      140
  """
  @spec normalize(integer(), Calibration.t()) :: integer()
  def normalize(raw_value, %Calibration{} = calibration) do
    adjusted_value =
      raw_value
      |> adjust_for_inversion(calibration)
      |> adjust_for_rollover(calibration)

    clamped = clamp(adjusted_value, calibration.min_value, calibration.max_value)

    clamped - calibration.min_value
  end

  @doc """
  Returns the total travel range for a calibration.
  """
  @spec total_travel(Calibration.t()) :: integer()
  def total_travel(%Calibration{} = calibration) do
    calibration.max_value - calibration.min_value
  end

  # Private functions

  # For inverted inputs, the Analyzer stores min_value and max_value as the
  # already-inverted values (1023 - raw). So Calculator doesn't need to do
  # any inversion - just use the values as-is, but apply the same inversion
  # to the incoming raw value.
  defp adjust_for_inversion(value, %Calibration{is_inverted: false}), do: value

  defp adjust_for_inversion(value, %Calibration{is_inverted: true} = calibration) do
    calibration.max_hardware_value - value
  end

  defp adjust_for_rollover(value, %Calibration{has_rollover: false}), do: value

  defp adjust_for_rollover(value, %Calibration{has_rollover: true} = calibration) do
    # If value is below min_value, it has wrapped around
    if value < calibration.min_value do
      value + calibration.max_hardware_value + 1
    else
      value
    end
  end

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
