defmodule TswIo.Hardware.Input.Calibration do
  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Hardware.Input

  schema "device_input_calibrations" do
    field :max_hardware_value, :integer
    field :min_value, :integer
    field :max_value, :integer
    field :has_rollover, :boolean, default: false
    field :is_inverted, :boolean, default: false

    belongs_to :input, Input

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(calibration, attrs) do
    calibration
    |> cast(attrs, [
      :max_hardware_value,
      :min_value,
      :max_value,
      :has_rollover,
      :is_inverted,
      :input_id
    ])
    |> validate_required([
      :max_hardware_value,
      :min_value,
      :max_value,
      :has_rollover,
      :is_inverted,
      :input_id
    ])
  end
end
