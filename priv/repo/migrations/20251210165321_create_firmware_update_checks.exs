defmodule TswIo.Repo.Migrations.CreateFirmwareUpdateChecks do
  use Ecto.Migration

  def change do
    create table(:firmware_update_checks) do
      add :checked_at, :utc_datetime, null: false
      add :found_updates, :boolean, default: false
      add :latest_version, :string
      add :error_message, :string

      timestamps(type: :utc_datetime)
    end

    create index(:firmware_update_checks, [:checked_at])
  end
end
