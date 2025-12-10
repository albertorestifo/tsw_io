defmodule TswIo.Firmware.UploadHistory do
  @moduledoc """
  Schema for firmware upload history.

  Tracks all firmware upload attempts for auditing and debugging purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TswIo.Firmware.BoardConfig
  alias TswIo.Firmware.FirmwareFile

  @type status :: :started | :completed | :failed | :cancelled

  @type t :: %__MODULE__{
          id: integer() | nil,
          upload_id: String.t() | nil,
          port: String.t() | nil,
          board_type: BoardConfig.board_type() | nil,
          firmware_file_id: integer() | nil,
          firmware_file: FirmwareFile.t() | Ecto.Association.NotLoaded.t() | nil,
          status: status() | nil,
          error_message: String.t() | nil,
          avrdude_output: String.t() | nil,
          duration_ms: integer() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "firmware_upload_history" do
    field :upload_id, :string
    field :port, :string
    field :board_type, Ecto.Enum, values: BoardConfig.board_types()
    field :status, Ecto.Enum, values: [:started, :completed, :failed, :cancelled]
    field :error_message, :string
    field :avrdude_output, :string
    field :duration_ms, :integer
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :firmware_file, FirmwareFile

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new upload history entry.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = history, attrs) do
    history
    |> cast(attrs, [
      :upload_id,
      :port,
      :board_type,
      :firmware_file_id,
      :status,
      :error_message,
      :avrdude_output,
      :duration_ms,
      :started_at,
      :completed_at
    ])
    |> validate_required([:upload_id, :port, :board_type, :status])
    |> foreign_key_constraint(:firmware_file_id)
  end

  @doc """
  Creates a changeset for starting a new upload.
  """
  @spec start_changeset(map()) :: Ecto.Changeset.t()
  def start_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:upload_id, :port, :board_type, :firmware_file_id])
    |> validate_required([:upload_id, :port, :board_type])
    |> put_change(:status, :started)
    |> put_change(:started_at, DateTime.utc_now())
  end

  @doc """
  Creates a changeset for marking an upload as completed.
  """
  @spec complete_changeset(t(), map()) :: Ecto.Changeset.t()
  def complete_changeset(%__MODULE__{} = history, attrs \\ %{}) do
    now = DateTime.utc_now()

    duration_ms =
      if history.started_at do
        DateTime.diff(now, history.started_at, :millisecond)
      end

    history
    |> cast(attrs, [:avrdude_output])
    |> put_change(:status, :completed)
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Creates a changeset for marking an upload as failed.
  """
  @spec fail_changeset(t(), String.t(), String.t() | nil) :: Ecto.Changeset.t()
  def fail_changeset(%__MODULE__{} = history, error_message, avrdude_output \\ nil) do
    now = DateTime.utc_now()

    duration_ms =
      if history.started_at do
        DateTime.diff(now, history.started_at, :millisecond)
      end

    history
    |> change()
    |> put_change(:status, :failed)
    |> put_change(:error_message, error_message)
    |> put_change(:avrdude_output, avrdude_output)
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Creates a changeset for marking an upload as cancelled.
  """
  @spec cancel_changeset(t()) :: Ecto.Changeset.t()
  def cancel_changeset(%__MODULE__{} = history) do
    now = DateTime.utc_now()

    duration_ms =
      if history.started_at do
        DateTime.diff(now, history.started_at, :millisecond)
      end

    history
    |> change()
    |> put_change(:status, :cancelled)
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end
end
