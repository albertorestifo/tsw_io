defmodule TswIo.Hardware.Device do
  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Hardware.Input

  schema "devices" do
    field :name, :string
    field :config_id, :integer

    has_many :inputs, Input

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:name, :config_id])
    |> validate_required([:name])
    |> unique_constraint(:config_id)
  end
end
