defmodule TswIoWeb.HealthController do
  @moduledoc """
  Health check endpoint for verifying app readiness.

  Returns 200 OK only when:
  - Database is accessible
  - Migrations are complete (by querying a known table)

  Used by Tauri to wait for full app startup before showing the main window.
  """

  use TswIoWeb, :controller

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
    # Using a simple raw query to check if the database is accessible
    # and migrations have run (configurations table should exist)
    case Repo.query("SELECT 1 FROM configurations LIMIT 1", [], timeout: 5000) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        # Check if this is an undefined table error (migrations not complete)
        case error do
          %{postgres: %{code: :undefined_table}} ->
            {:error, "migrations_pending"}

          _ ->
            {:error, "database_unavailable"}
        end
    end
  rescue
    DBConnection.ConnectionError ->
      {:error, "database_unavailable"}

    _ ->
      {:error, "unknown"}
  end
end
