defmodule TokenManager.Seeds do
  alias TokenManager.Repo
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.StateManager.TokenStateManager

  def run do
    token_count = Repo.aggregate(TokenSchema, :count)

    if token_count < 100 do
      tokens_to_create = 100 - token_count
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      tokens =
        Enum.map(1..tokens_to_create, fn _ ->
          %{
            id: Ecto.UUID.generate(),
            status: :available,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(TokenSchema, tokens)

      created_tokens =
        TokenSchema
        |> Repo.all()
        |> Repo.preload(:token_usages)

      TokenStateManager.add_tokens(created_tokens)

      IO.puts("Created #{count} new tokens and updated state manager")
    end
  end
end

TokenManager.Seeds.run()
