defmodule TswIo.Repo do
  use Ecto.Repo,
    otp_app: :tsw_io,
    adapter: Ecto.Adapters.SQLite3
end
