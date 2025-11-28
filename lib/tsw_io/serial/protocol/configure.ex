defmodule TswIo.Serial.Protocol.Configure do
  @moduledoc """
  Configuration message sent to device to configure an input.

  Each input is sent as a separate Configure message. The device uses
  `total_parts` and `part_number` to know when the full configuration
  is received.
  """

  alias TswIo.Serial.Protocol.Message

  @behaviour Message

  @type input_type :: :analog

  @type t() :: %__MODULE__{
          config_id: integer(),
          total_parts: integer(),
          part_number: integer(),
          input_type: input_type(),
          pin: integer(),
          sensitivity: integer()
        }

  defstruct [:config_id, :total_parts, :part_number, :input_type, :pin, :sensitivity]

  @impl Message
  def type(), do: 0x02

  @impl Message
  def encode(%__MODULE__{
        config_id: config_id,
        total_parts: total_parts,
        part_number: part_number,
        input_type: :analog,
        pin: pin,
        sensitivity: sensitivity
      }) do
    {:ok,
     <<0x02, config_id::little-32-unsigned, total_parts::8-unsigned, part_number::8-unsigned,
       0x00::8-unsigned, pin::8-unsigned, sensitivity::8-unsigned>>}
  end

  @impl Message
  def decode(
        <<0x02, config_id::little-32-unsigned, total_parts::8-unsigned, part_number::8-unsigned,
          0x00, pin::8-unsigned, sensitivity::8-unsigned>>
      ) do
    {:ok,
     %__MODULE__{
       config_id: config_id,
       total_parts: total_parts,
       part_number: part_number,
       input_type: :analog,
       pin: pin,
       sensitivity: sensitivity
     }}
  end

  @impl Message
  def decode(_) do
    {:error, :invalid_message}
  end
end
