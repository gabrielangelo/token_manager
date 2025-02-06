import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :token_manager, TokenManager.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "token_manager_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :token_manager, TokenManagerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pArvmVcR5trVwyUASZYC7375QQkkyzSOLqM+219bi5h4UhLj4T9ZsggGSEfz6XW2",
  server: false

# In test we don't send emails
config :token_manager, TokenManager.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :token_manager, Oban, testing: :manual
