defmodule TokenManager.Repo.Migrations.CreateTokenUsagesTable do
  use Ecto.Migration

  def change do
    create table(:token_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token_id, references(:tokens, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:token_usages, [:token_id])
    create index(:token_usages, [:user_id])
    create index(:token_usages, [:started_at])
    create index(:token_usages, [:ended_at])

    create index(:token_usages, [:token_id, :ended_at])
  end
end
