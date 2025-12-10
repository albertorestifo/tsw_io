defmodule TswIo.Firmware.FirmwareFile do
  @moduledoc """
  Schema for individual firmware files (HEX files) per board type.

  Each release has multiple firmware files, one for each supported
  Arduino board type (Uno, Nano, Leonardo, etc.).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Firmware.BoardConfig
  alias TswIo.Firmware.FirmwareRelease

  @type t :: %__MODULE__{
          id: integer() | nil,
          firmware_release_id: integer() | nil,
          firmware_release: FirmwareRelease.t() | Ecto.Association.NotLoaded.t(),
          board_type: BoardConfig.board_type() | nil,
          download_url: String.t() | nil,
          file_path: String.t() | nil,
          file_size: integer() | nil,
          checksum_sha256: String.t() | nil,
          downloaded_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "firmware_files" do
    belongs_to :firmware_release, FirmwareRelease

    field :board_type, Ecto.Enum, values: BoardConfig.board_types()
    field :download_url, :string
    field :file_path, :string
    field :file_size, :integer
    field :checksum_sha256, :string
    field :downloaded_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a firmware file.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = file, attrs) do
    file
    |> cast(attrs, [
      :firmware_release_id,
      :board_type,
      :download_url,
      :file_path,
      :file_size,
      :checksum_sha256,
      :downloaded_at
    ])
    |> validate_required([:firmware_release_id, :board_type, :download_url])
    |> foreign_key_constraint(:firmware_release_id)
    |> unique_constraint([:firmware_release_id, :board_type])
  end

  @doc """
  Returns true if this firmware file has been downloaded and cached locally.
  """
  @spec downloaded?(t()) :: boolean()
  def downloaded?(%__MODULE__{file_path: nil}), do: false
  def downloaded?(%__MODULE__{downloaded_at: nil}), do: false
  def downloaded?(%__MODULE__{}), do: true
end
