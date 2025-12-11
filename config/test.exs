import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tsw_io, TswIo.Repo,
  database: Path.expand("../tsw_io_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  # Prevent "Database busy" errors in CI by waiting for write lock
  busy_timeout: 5000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tsw_io, TswIoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "NvZHOhdHQPBJ0Es1QVYQfVjXzJ9sSiQLWARJBAYZBR4yh+YZ3u0/M0d6grAy8QMQ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable Simulator.Connection GenServer in tests to avoid database conflicts
# with Ecto.Adapters.SQL.Sandbox. Tests that need this GenServer can start it
# manually with proper sandbox access.
config :tsw_io, :start_simulator_connection, false

# Disable LeverController GenServer in tests to avoid pubsub conflicts.
config :tsw_io, :start_lever_controller, false

# Disable UpdateChecker GenServer in tests to avoid state pollution across tests.
# The GenServer performs automatic periodic checks and retains state, making it
# difficult to test in isolation. Tests can start it manually if needed.
config :tsw_io, :start_update_checker, false

# Disable AppVersion.UpdateChecker GenServer in tests for the same reasons.
config :tsw_io, :start_app_version_checker, false
