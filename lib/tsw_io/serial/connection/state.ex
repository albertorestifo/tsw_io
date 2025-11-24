defmodule TswIo.Serial.Connection.State do
  alias TswIo.Serial.Connection.DeviceConnection

  @type t :: %__MODULE__{
          devices: [DeviceConnection.t()]
        }

  defstruct devices: []
end
