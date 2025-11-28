defmodule TswIo.Hardware.Calibration.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for calibration sessions.

  Calibration sessions are temporary processes that live for the duration
  of a calibration workflow. This supervisor manages their lifecycle.
  """

  use DynamicSupervisor

  alias TswIo.Hardware.Calibration.Session

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a calibration session under supervision.

  ## Options

    * `:input_id` - Required. The input ID being calibrated.
    * `:port` - Required. The serial port of the device.
    * `:pin` - Required. The pin number of the input.
    * `:max_hardware_value` - Optional. Hardware max value (default: 1023).

  Returns `{:ok, pid}` on success.
  """
  @spec start_session(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_session(opts) do
    spec = {Session, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
