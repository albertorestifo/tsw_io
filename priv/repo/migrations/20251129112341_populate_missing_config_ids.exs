defmodule TswIo.Repo.Migrations.PopulateMissingConfigIds do
  use Ecto.Migration

  @max_i32 2_147_483_647

  def up do
    # Get all devices with null config_id
    devices_query = "SELECT id FROM devices WHERE config_id IS NULL"

    {:ok, %{rows: rows}} = repo().query(devices_query)

    for [id] <- rows do
      config_id = generate_unique_config_id()

      execute("UPDATE devices SET config_id = #{config_id} WHERE id = #{id}")
    end
  end

  def down do
    # No-op: we don't want to remove config_ids on rollback
    :ok
  end

  defp generate_unique_config_id do
    config_id = :rand.uniform(@max_i32)

    # Check if it already exists
    {:ok, %{rows: rows}} =
      repo().query("SELECT 1 FROM devices WHERE config_id = #{config_id} LIMIT 1")

    if rows == [] do
      config_id
    else
      generate_unique_config_id()
    end
  end
end
