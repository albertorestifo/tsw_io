defmodule TswIo.Train.Notch do
  @moduledoc """
  Schema for lever notches.

  A notch represents a discrete position or range on a lever. Notches can be
  of two types:
  - `:gate` - A fixed position with a single value
  - `:linear` - A continuous range with min and max values

  Each notch can have an optional description for user reference.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Train.LeverConfig

  @type notch_type :: :gate | :linear

  @type t :: %__MODULE__{
          id: integer() | nil,
          lever_config_id: integer() | nil,
          index: integer() | nil,
          type: notch_type() | nil,
          value: float() | nil,
          min_value: float() | nil,
          max_value: float() | nil,
          description: String.t() | nil,
          lever_config: LeverConfig.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "train_lever_notches" do
    field :index, :integer
    field :type, Ecto.Enum, values: [:gate, :linear]
    field :value, :float
    field :min_value, :float
    field :max_value, :float
    field :description, :string

    belongs_to :lever_config, LeverConfig

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = notch, attrs) do
    notch
    |> cast(attrs, [:index, :type, :value, :min_value, :max_value, :description, :lever_config_id])
    |> round_float_fields([:value, :min_value, :max_value])
    |> validate_required([:index, :type])
    |> validate_notch_values()
    |> foreign_key_constraint(:lever_config_id)
    |> unique_constraint([:lever_config_id, :index])
  end

  defp validate_notch_values(changeset) do
    case get_field(changeset, :type) do
      :gate ->
        changeset
        |> validate_required([:value])

      :linear ->
        changeset
        |> validate_required([:min_value, :max_value])

      _ ->
        changeset
    end
  end

  # Round float fields to 2 decimal places to avoid precision artifacts
  defp round_float_fields(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      case get_change(cs, field) do
        nil -> cs
        value when is_float(value) -> put_change(cs, field, Float.round(value, 2))
        _ -> cs
      end
    end)
  end
end
