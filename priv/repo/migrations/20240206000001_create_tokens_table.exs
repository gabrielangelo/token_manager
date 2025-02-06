defmodule TokenManager.Repo.Migrations.CreateTokensTable do
  use Ecto.Migration

  def change do
    create table(:tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "available"
      add :current_user_id, :binary_id
      add :activated_at, :utc_datetime

      timestamps()
    end

    create index(:tokens, [:status])
    create index(:tokens, [:current_user_id])
    create index(:tokens, [:activated_at])
  end
end
