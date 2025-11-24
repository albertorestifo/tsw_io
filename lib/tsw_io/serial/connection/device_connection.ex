defmodule TswIo.Serial.Connection.DeviceConnection do
  @moduledoc """
  Represents a connection to a specific TWS device over a serial port.
  """

  alias TswIo.Device

  @type t :: %__MODULE__{
          port: String.t(),
          pid: pid(),
          device: Device.t() | nil
        }

  defstruct [:port, :pid, :device]
end
