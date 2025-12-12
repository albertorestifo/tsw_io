defmodule TswIoWeb.HealthController do
  @moduledoc """
  Health check endpoint for verifying app readiness.

  Returns 200 OK only when:
  - Database is accessible
  - Migrations are complete (by querying a known table)

  Used by Tauri to wait for full app startup before showing the main window.
  """

  use TswIoWeb, :controller

  import Ecto.Query

  alias TswIo.Firmware.FirmwareRelease
  alias TswIo.Repo

  def index(conn, _params) do
    case check_database_ready() do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(503)
        |> json(%{status: "unavailable", reason: reason})
    end
  end

  defp check_database_ready do
    # Try to query a table that exists after migrations
    # Using Ecto query to check if the database is accessible
    # and migrations have run (firmware_releases table should exist)
    try do
      # Simple existence check - just see if we can query the table
      Repo.exists?(from(r in FirmwareRelease, limit: 1))
      :ok
    rescue
      Ecto.QueryError ->
        {:error, "migrations_pending"}

      DBConnection.ConnectionError ->
        {:error, "database_unavailable"}

      _ ->
        {:error, "unknown"}
    end
  end
end
