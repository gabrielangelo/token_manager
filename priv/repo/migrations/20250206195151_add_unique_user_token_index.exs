defmodule TokenManager.Repo.Migrations.AddUniqueUserTokenIndex do
  use Ecto.Migration

  def up do
    create unique_index(:tokens, [:current_user_id],
             where: "status = 'active' AND current_user_id IS NOT NULL",
             name: :unique_active_user_token_index
           )
  end

  def down do
    execute "ALTER TABLE tokens DROP CONSTRAINT unique_active_user_token"

    drop index(:tokens, [:current_user_id], name: :unique_active_user_token_index)
  end
end
