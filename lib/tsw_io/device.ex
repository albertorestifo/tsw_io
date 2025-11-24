defmodule TswIo.Device do
  @moduledoc """
  Represents a TWS device that has been identified.
  """

  @type t :: %__MODULE__{
          id: integer(),
          version: integer(),
          config_id: integer() | nil
        }

  defstruct [:id, :version, :config_id]
end
