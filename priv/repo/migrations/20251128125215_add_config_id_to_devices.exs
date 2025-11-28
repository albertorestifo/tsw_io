defmodule TswIo.Repo.Migrations.AddConfigIdToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :config_id, :integer
    end

    create unique_index(:devices, [:config_id])

    # Add unique constraint for device_id + pin combination
    create unique_index(:device_inputs, [:device_id, :pin])
  end
end
