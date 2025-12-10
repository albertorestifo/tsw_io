defmodule TswIo.Repo.Migrations.RemoveFirmwareDownloadTracking do
  use Ecto.Migration

  def change do
    alter table(:firmware_files) do
      remove :file_path, :string
      remove :downloaded_at, :utc_datetime
    end
  end
end
