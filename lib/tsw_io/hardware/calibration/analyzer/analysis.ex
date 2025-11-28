defmodule TswIo.Hardware.Calibration.Analyzer.Analysis do
  @moduledoc """
  Represents the result of analyzing calibration sweep data.

  Contains boolean flags for detected input characteristics:
  - `inverted` - input values decrease as physical position increases
  - `rollover` - values wrap from max (1023) to 0 during sweep
  """

  @enforce_keys [:inverted, :rollover]
  defstruct [:inverted, :rollover]

  @type t :: %__MODULE__{
          inverted: boolean(),
          rollover: boolean()
        }
end
