defmodule TswIo.Repo.Migrations.CreateFirmwareTables do
  use Ecto.Migration

  def change do
    # firmware_releases - cached GitHub release metadata
    create table(:firmware_releases) do
      add :version, :string, null: false
      add :tag_name, :string, null: false
      add :release_url, :string
      add :release_notes, :text
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:firmware_releases, [:tag_name])

    # firmware_files - individual .hex files per board type
    create table(:firmware_files) do
      add :firmware_release_id, references(:firmware_releases, on_delete: :delete_all),
        null: false

      add :board_type, :string, null: false
      add :download_url, :string, null: false
      add :file_path, :string
      add :file_size, :integer
      add :checksum_sha256, :string
      add :downloaded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:firmware_files, [:firmware_release_id, :board_type])
    create index(:firmware_files, [:board_type])

    # firmware_upload_history - audit trail for uploads
    create table(:firmware_upload_history) do
      add :upload_id, :string, null: false
      add :port, :string, null: false
      add :board_type, :string, null: false
      add :firmware_file_id, references(:firmware_files, on_delete: :nilify_all)
      add :status, :string, null: false
      add :error_message, :text
      add :avrdude_output, :text
      add :duration_ms, :integer
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:firmware_upload_history, [:status])
    create index(:firmware_upload_history, [:started_at])
  end
end
