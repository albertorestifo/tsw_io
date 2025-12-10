defmodule TswIo.Firmware.FirmwareRelease do
  @moduledoc """
  Schema for firmware releases fetched from GitHub.

  Each release represents a version of the tsw_board firmware
  that can be downloaded and flashed to compatible devices.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Firmware.FirmwareFile

  @type t :: %__MODULE__{
          id: integer() | nil,
          version: String.t() | nil,
          tag_name: String.t() | nil,
          release_url: String.t() | nil,
          release_notes: String.t() | nil,
          published_at: DateTime.t() | nil,
          firmware_files: [FirmwareFile.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "firmware_releases" do
    field :version, :string
    field :tag_name, :string
    field :release_url, :string
    field :release_notes, :string
    field :published_at, :utc_datetime

    has_many :firmware_files, FirmwareFile

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a firmware release.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = release, attrs) do
    release
    |> cast(attrs, [:version, :tag_name, :release_url, :release_notes, :published_at])
    |> validate_required([:version, :tag_name])
    |> unique_constraint(:tag_name)
  end
end
