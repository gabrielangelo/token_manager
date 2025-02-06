defmodule TokenManager.Seeds do
  alias TokenManager.Repo
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema

  def run do
    token_count =
      TokenSchema
      |> Repo.aggregate(:count)

    if token_count < 100 do
      tokens =
        Enum.map(1..(100 - token_count), fn _ ->
          %{
            id: Ecto.UUID.generate(),
            status: :available,
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        end)

      Repo.insert_all(TokenSchema, tokens)
    end
  end
end

# TokenManager.Seeds.run()
