defmodule TokenManager.Repo do
  use Ecto.Repo,
    otp_app: :token_manager,
    adapter: Ecto.Adapters.Postgres
end
