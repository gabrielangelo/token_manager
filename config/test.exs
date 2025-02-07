import Config

# Configure your database

# Determine if we're running in Docker
docker_env = System.get_env("IN_DOCKER_TEST") == "true"

database_url =
  if docker_env do
    # Docker database configuration
    "ecto://postgres:postgres@db_test:5432/token_manager_test"
  else
    # Local database configuration
    "ecto://postgres:postgres@localhost:5432/token_manager_test"
  end

# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :token_manager, TokenManager.Repo,
  url: System.get_env("DATABASE_URL") || database_url,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :token_manager, TokenManagerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_only_secret_key_base",
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
