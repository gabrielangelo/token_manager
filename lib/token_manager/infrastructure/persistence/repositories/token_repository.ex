defmodule TokenManager.Infrastructure.Repositories.TokenRepository do
  @moduledoc """
  Handles persistence and retrieval of tokens and their usage records in the database.
  Implements optimistic locking strategies to handle concurrent access, maintains token
  state transitions, and provides comprehensive querying capabilities for token metrics
  and history. All database operations are performed with ACID guarantees, ensuring
  data consistency even under high concurrency conditions.
  """
  alias TokenManager.Domain.Token
  alias TokenManager.Domain.Token.TokenUsage

  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema
  alias TokenManager.Repo

  import Ecto.Query

  @type token_stats :: %{
          total_tokens: non_neg_integer(),
          active_tokens: non_neg_integer(),
          active_usages: non_neg_integer()
        }

  @doc """
  Returns the total count of tokens in the system.
  """
  @spec count_total_tokens() :: non_neg_integer()
  def count_total_tokens do
    TokenSchema
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the count of currently active tokens.
  """
  @spec count_active_tokens() :: non_neg_integer()
  def count_active_tokens do
    TokenSchema
    |> where([t], t.status == :active)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the count of active token usages (those without an end date).
  """
  @spec count_active_usages() :: non_neg_integer()
  def count_active_usages do
    TokenUsageSchema
    |> where([tu], is_nil(tu.ended_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Retrieves token usage history ordered by most recent first.

  Returns a list of domain TokenUsage entities.
  """
  @spec get_token_history(binary()) :: [TokenUsage.t()]
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
  @spec get_token!(binary()) :: Token.t() | no_return()
  def get_token!(id) do
    TokenSchema
    |> where([t], t.id == ^id)
    |> preload(:token_usages)
    |> Repo.one!()
    |> TokenSchema.to_domain()
  end

  @spec get_token(binary()) :: {:ok, Token.t()} | {:error, atom()}
  def get_token(id) do
    TokenSchema
    |> where([t], t.id == ^id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :token_not_found}

      token ->
        {:ok, token |> Repo.preload(:token_usages) |> TokenSchema.to_domain()}
    end
  end

  @doc """
  Retrieves an available token using SELECT FOR UPDATE SKIP LOCKED
  to handle concurrent access.

  Returns nil if no available tokens exist.
  """
  @spec get_available_token() :: Token.t() | nil
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
  @spec get_oldest_active_token() :: Token.t() | nil
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
  @spec update(Token.t()) :: {:ok, Token.t()} | {:error, Ecto.Changeset.t()}
  def update(token) do
    with existing_token <- get_token!(token.id),
         changeset <- prepare_update_changeset(existing_token, token),
         {:ok, updated_schema} <- Repo.update(changeset) do
      {:ok, convert_to_domain_with_usages(updated_schema)}
    end
  end

  defp prepare_update_changeset(existing_schema, token) do
    update_attrs = %{
      status: token.status,
      current_user_id: token.current_user_id,
      activated_at: token.activated_at
    }

    existing_schema
    |> TokenSchema.from_domain()
    |> TokenSchema.changeset(update_attrs)
  end

  defp convert_to_domain_with_usages(schema) do
    schema
    |> Repo.preload(:token_usages)
    |> TokenSchema.to_domain()
  end

  @doc """
  Creates a new token usage record.

  Returns `{:ok, token_usage}` on success or `{:error, changeset}` on failure.
  """
  @spec create_usage(TokenUsage.t()) :: {:ok, TokenUsage.t()} | {:error, Ecto.Changeset.t()}
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
      {:error, _error} = error -> error
    end
  end

  @doc """
  Updates a token usage record, typically to set its end date.

  Returns `{:ok, token_usage}` on success or `{:error, changeset}` on failure.
  """
  @spec update_usage(TokenUsage.t()) :: {:ok, TokenUsage.t()} | {:error, Ecto.Changeset.t()}
  def update_usage(token_usage) do
    token_usage
    |> TokenUsageSchema.from_domain()
    |> TokenUsageSchema.changeset(%{ended_at: token_usage.ended_at})
    |> Repo.update()
    |> case do
      {:ok, schema} -> {:ok, TokenUsageSchema.to_domain(schema)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Retrieves the active usage record for a token.
  A token can have at most one active usage at a time.

  Returns nil if no active usage exists.
  """
  @spec get_active_usage(binary()) :: TokenUsage.t() | nil
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
  @spec clear_active_tokens() :: {:ok, non_neg_integer()} | {:error, atom()}
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
  @spec close_all_active_usages() :: {:ok, non_neg_integer()} | {:error, atom()}
  def close_all_active_usages do
    now = DateTime.utc_now()

    {count, _} =
      TokenUsageSchema
      |> where([tu], is_nil(tu.ended_at))
      |> Repo.update_all(set: [ended_at: now])

    {:ok, count}
  end

  @doc """
  Lists all tokens in the system with their usage records.

  Returns a list of domain Token entities.
  """
  @spec list_tokens() :: [Token.t()]
  def list_tokens do
    TokenSchema
    |> order_by([t], desc: t.activated_at, desc: t.inserted_at)
    |> Repo.all()
    |> Enum.map(&TokenSchema.to_domain/1)
  end

  @doc """
  Gets a user's active token, if any exists.

  Returns nil if the user has no active token.
  """
  @spec get_user_active_token(binary()) :: Token.t() | nil
  def get_user_active_token(user_id) do
    TokenSchema
    |> where([t], t.status == :active and t.current_user_id == ^user_id)
    |> preload(:token_usages)
    |> Repo.one()
    |> maybe_to_domain()
  end

  @doc """
  Executes the given function within a database transaction.
  """
  @spec transaction((-> result)) :: {:ok, result} | {:error, term()} when result: term()
  def transaction(fun), do: Repo.transaction(fun)

  defp maybe_to_domain(nil), do: nil
  defp maybe_to_domain(schema), do: TokenSchema.to_domain(schema)
  defp maybe_to_domain(nil, _schema_module), do: nil
  defp maybe_to_domain(schema, schema_module), do: schema_module.to_domain(schema)
end
