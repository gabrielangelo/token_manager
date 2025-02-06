defmodule TokenManager.Infrastructure.Repositories.TokenRepository do
  @moduledoc """
  Repository for token-related database operations
  """

  import Ecto.Query
  alias TokenManager.Repo
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema

  def count_total_tokens do
    TokenSchema
    |> Repo.aggregate(:count)
  end

  def count_active_tokens do
    TokenSchema
    |> where([t], t.status == :active)
    |> Repo.aggregate(:count)
  end

  def count_active_usages do
    TokenUsageSchema
    |> where([tu], is_nil(tu.ended_at))
    |> Repo.aggregate(:count)
  end

  def get_token_history(token_id) do
    TokenUsageSchema
    |> where([tu], tu.token_id == ^token_id)
    |> order_by([tu], desc: tu.inserted_at)
    |> Repo.all()
    |> Enum.map(&TokenUsageSchema.to_domain/1)
  end

  def get_token!(id) do
    TokenSchema
    |> where([t], t.id == ^id)
    |> preload(:token_usages)
    |> Repo.one!()
    |> TokenSchema.to_domain()
  end

  @spec get_available_token() :: nil | TokenManager.Domain.Token.t()
  def get_available_token do
    TokenSchema
    |> where([t], t.status == :available)
    |> limit(1)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.one()
    |> maybe_to_domain()
  end

  def get_oldest_active_token do
    TokenSchema
    |> where([t], t.status == :active)
    |> order_by([t], asc: t.activated_at)
    |> limit(1)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> maybe_to_domain()
  end

  def update(token) do
    case get_token!(token.id) do
      existing_schema ->
        existing_schema
        |> TokenSchema.from_domain()
        |> TokenSchema.changeset(%{
          status: token.status,
          current_user_id: token.current_user_id,
          activated_at: token.activated_at
        })
        |> Repo.update()
        |> case do
          {:ok, updated_schema} ->
            {:ok, updated_schema |> Repo.preload(:token_usages) |> TokenSchema.to_domain()}
          error ->
            error
        end
    end
  end

  def create_usage(token_usage) do
    token_usage
    |> TokenUsageSchema.from_domain()
    |> TokenUsageSchema.changeset(%{
      token_id: token_usage.token_id,
      user_id: token_usage.user_id,
      started_at: token_usage.started_at
    })
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, TokenUsageSchema.to_domain(schema)}
      error -> error
    end
  end

  def update_usage(token_usage) do
    token_usage
    |> TokenUsageSchema.from_domain()
    |> TokenUsageSchema.changeset(%{ended_at: token_usage.ended_at})
    |> Repo.update()
    |> case do
      {:ok, schema} -> {:ok, TokenUsageSchema.to_domain(schema)}
      error -> error
    end
  end

  def get_active_usage(token_id) do
    TokenUsageSchema
    |> where([tu], tu.token_id == ^token_id and is_nil(tu.ended_at))
    |> Repo.one()
    |> maybe_to_domain(TokenUsageSchema)
  end

  def clear_active_tokens do
    {count, _} =
      TokenSchema
      |> where([t], t.status == :active)
      |> Repo.update_all(
        set: [
          status: :available,
          current_user_id: nil,
          activated_at: nil
        ]
      )

    {:ok, count}
  end

  def close_all_active_usages do
    now = DateTime.utc_now()

    {count, _} =
      TokenUsageSchema
      |> where([tu], is_nil(tu.ended_at))
      |> Repo.update_all(set: [ended_at: now])

    {:ok, count}
  end

  def transaction(fun), do: Repo.transaction(fun)

  defp maybe_to_domain(nil), do: nil
  defp maybe_to_domain(schema), do: TokenSchema.to_domain(schema)
  defp maybe_to_domain(schema, schema_module), do: schema_module.to_domain(schema)
end
