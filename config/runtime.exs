import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/tsw_io start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
#
# For desktop releases (Burrito), server is always enabled.
if System.get_env("PHX_SERVER") || System.get_env("BURRITO") do
  config :tsw_io, TswIoWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Determine platform-specific data directory for the database.
  # Can be overridden with DATABASE_PATH environment variable.
  database_path =
    System.get_env("DATABASE_PATH") ||
      (fn ->
        app_name = "TswIo"
        app_name_lower = "tsw_io"

        data_dir =
          case :os.type() do
            {:unix, :darwin} ->
              # macOS: ~/Library/Application Support/TswIo
              home = System.get_env("HOME") || "~"
              Path.join([home, "Library", "Application Support", app_name])

            {:win32, _} ->
              # Windows: %APPDATA%/TswIo
              appdata = System.get_env("APPDATA") || System.get_env("LOCALAPPDATA") || "."
              Path.join(appdata, app_name)

            {:unix, _} ->
              # Linux/BSD: $XDG_DATA_HOME/tsw_io or ~/.local/share/tsw_io
              xdg_data = System.get_env("XDG_DATA_HOME")

              base_dir =
                if xdg_data && xdg_data != "" do
                  xdg_data
                else
                  home = System.get_env("HOME") || "~"
                  Path.join([home, ".local", "share"])
                end

              Path.join(base_dir, app_name_lower)
          end

        # Ensure directory exists
        File.mkdir_p!(data_dir)
        Path.join(data_dir, "#{app_name_lower}.db")
      end).()

  config :tsw_io, TswIo.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # For desktop releases, we generate a stable key based on machine identity.
  # For server deployments, use the SECRET_KEY_BASE environment variable.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      (fn ->
        # Generate a stable secret based on the data directory path
        # This ensures the same key is used across restarts on the same machine
        # SHA256 produces 32 bytes, encode16 produces 64 hex characters
        :crypto.hash(:sha256, database_path)
        |> Base.encode16(case: :lower)
      end).()

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :tsw_io, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :tsw_io, TswIoWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [
      ip: {127, 0, 0, 1},
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: false,
    server: true

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :tsw_io, TswIoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :tsw_io, TswIoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
