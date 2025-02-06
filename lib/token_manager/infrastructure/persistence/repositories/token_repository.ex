defmodule TokenManager.Infrastructure.Repositories.TokenRepository do
  @moduledoc """
  Handles persistence and retrieval of tokens and their usage records in the database.
  Implements optimistic locking strategies to handle concurrent access, maintains token
  state transitions, and provides comprehensive querying capabilities for token metrics
  and history. All database operations are performed with ACID guarantees, ensuring
  data consistency even under high concurrency conditions.
  """

  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema
  alias TokenManager.Repo
  import Ecto.Query

  @doc """
  Returns the total count of tokens in the system.
  """
  def count_total_tokens do
    TokenSchema
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the count of currently active tokens.
  """
  def count_active_tokens do
    TokenSchema
    |> where([t], t.status == :active)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the count of active token usages (those without an end date).
  """
  def count_active_usages do
    TokenUsageSchema
    |> where([tu], is_nil(tu.ended_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Retrieves token usage history ordered by most recent first.

  Returns a list of domain TokenUsage entities.
  """
  def get_token_history(token_id) do
    TokenUsageSchema
    |> where([tu], tu.token_id == ^token_id)
    |> order_by([tu], desc: tu.inserted_at)
    |> Repo.all()
    |> Enum.map(&TokenUsageSchema.to_domain/1)
  end

  @doc """
  Fetches a token by ID with preloaded usage history.
  Raises if token is not found.

  Returns a domain Token entity.
  """
  def get_token!(id) do
    TokenSchema
    |> where([t], t.id == ^id)
    |> preload(:token_usages)
    |> Repo.one!()
    |> TokenSchema.to_domain()
  end

  @doc """
  Retrieves an available token using SELECT FOR UPDATE SKIP LOCKED
  to handle concurrent access.

  Returns nil if no available tokens exist.
  """
  @spec get_available_token() :: nil | TokenManager.Domain.Token.t()
  def get_available_token do
    TokenSchema
    |> where([t], t.status == :available)
    |> limit(1)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.one()
    |> maybe_to_domain()
  end

  @doc """
  Retrieves the oldest active token using SELECT FOR UPDATE.
  Used for token reallocation when no available tokens exist.

  Returns nil if no active tokens exist.
  """
  def get_oldest_active_token do
    TokenSchema
    |> where([t], t.status == :active)
    |> order_by([t], asc: t.activated_at)
    |> limit(1)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> maybe_to_domain()
  end

  @doc """
  Updates a token's attributes and returns the updated domain entity.
  Preloads token usages after update.

  Returns `{:ok, token}` on success or `{:error, changeset}` on failure.
  """
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

  @doc """
  Creates a new token usage record.

  Returns `{:ok, token_usage}` on success or `{:error, changeset}` on failure.
  """
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

  @doc """
  Updates a token usage record, typically to set its end date.

  Returns `{:ok, token_usage}` on success or `{:error, changeset}` on failure.
  """
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

  @doc """
  Retrieves the active usage record for a token.
  A token can have at most one active usage at a time.

  Returns nil if no active usage exists.
  """
  def get_active_usage(token_id) do
    TokenUsageSchema
    |> where([tu], tu.token_id == ^token_id and is_nil(tu.ended_at))
    |> Repo.one()
    |> maybe_to_domain(TokenUsageSchema)
  end

  @doc """
  Releases all active tokens in a single operation.
  Used for system-wide cleanup or reset.

  Returns `{:ok, count}` where count is the number of tokens released.
  """
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

  @doc """
  Closes all active token usages by setting their end date.
  Used in conjunction with clear_active_tokens for system cleanup.

  Returns `{:ok, count}` where count is the number of usages closed.
  """
  def close_all_active_usages do
    now = DateTime.utc_now()

    {count, _} =
      TokenUsageSchema
      |> where([tu], is_nil(tu.ended_at))
      |> Repo.update_all(set: [ended_at: now])

    {:ok, count}
  end

  @doc """
  Executes the given function within a database transaction.
  """
  def transaction(fun), do: Repo.transaction(fun)

  # Private helper functions for domain conversion
  defp maybe_to_domain(nil), do: nil
  defp maybe_to_domain(schema), do: TokenSchema.to_domain(schema)
  defp maybe_to_domain(nil, _schema_module), do: nil
  defp maybe_to_domain(schema, schema_module), do: schema_module.to_domain(schema)
end
