defmodule TswIo.Hardware.Input do
  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Hardware.Device
  alias TswIo.Hardware.Input.Calibration

  schema "device_inputs" do
    field :pin, :integer
    field :input_type, Ecto.Enum, values: [:analog]
    field :sensitivity, :integer

    belongs_to :device, Device
    has_one :calibration, Calibration

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(input, attrs) do
    input
    |> cast(attrs, [:pin, :input_type, :sensitivity, :device_id])
    |> validate_required([:pin, :input_type, :sensitivity, :device_id])
    |> validate_number(:pin, greater_than: 0, less_than: 255)
    |> validate_number(:sensitivity, greater_than: 0, less_than_or_equal_to: 10)
    |> unique_constraint([:device_id, :pin])
  end
end
