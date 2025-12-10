defmodule TswIo.Firmware.UpdateCheck do
  @moduledoc """
  Schema for firmware update check history.

  Records when we checked for updates and whether new versions were found.
  Used for rate limiting and preventing excessive GitHub API calls.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          checked_at: DateTime.t() | nil,
          found_updates: boolean() | nil,
          latest_version: String.t() | nil,
          error_message: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "firmware_update_checks" do
    field :checked_at, :utc_datetime
    field :found_updates, :boolean, default: false
    field :latest_version, :string
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for recording an update check.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = check, attrs) do
    check
    |> cast(attrs, [:checked_at, :found_updates, :latest_version, :error_message])
    |> validate_required([:checked_at])
  end
end
