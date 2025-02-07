defmodule TokenManager.Domain.Token.TokenService do
  @moduledoc """
  Provides token lifecycle management functionality for a token-based access control system.
  The service maintains token state transitions, enforces access rules, and handles concurrent
  access through database transactions. It ensures that users can only hold one active token
  at a time and implements automatic token cleanup after periods of inactivity. The service
  maintains a comprehensive usage history, tracking when tokens are activated and released,
  while protecting against race conditions through transactional operations.
  """

  alias TokenManager.Domain.Token
  alias TokenManager.Domain.Token.TokenUsage
  alias TokenManager.Infrastructure.Repositories.TokenRepository
  alias TokenManager.Infrastructure.StateManager.TokenStateManager
  alias TokenManager.Infrastructure.Workers.TokenCleanupWorker

  @two_minutes 120

  @type error_reason ::
          :token_not_found
          | :invalid_token_state
          | :already_has_active_token
          | :database_error

  @type activation_result ::
          {:ok, %{token: Token.t(), token_usage: TokenUsage.t()}}
          | {:error, error_reason()}

  @doc """
  Checks if a token has expired and releases it if necessary.
  """
  @spec release_token_if_expired(binary()) ::
          {:ok, Token.t()} | {:error, :token_not_found | :token_not_expired | atom()}
  def release_token_if_expired(token_id) do
    TokenRepository.transaction(fn ->
      with {:ok, token} <- TokenRepository.get_token(token_id),
           usage when not is_nil(usage) <- TokenRepository.get_active_usage(token.id),
           true <- token_expired?(token),
           {:ok, _usage} <- close_token_usage(token),
           {:ok, released_token} <- release_token(token) do
        TokenStateManager.mark_token_available(token_id)
        {:ok, released_token}
      else
        {:error, _} = error -> error
        nil -> {:error, :token_not_found}
        false -> {:error, :token_not_expired}
      end
    end)
  end

  defp token_expired?(token) do
    case DateTime.compare(
           DateTime.add(token.activated_at, @two_minutes),
           DateTime.utc_now()
         ) do
      :lt -> true
      _ -> false
    end
  end

  @doc """
  Retrieves a token by its ID.

  Raises if token is not found.
  """
  @spec get_token!(binary()) :: Token.t() | no_return()
  def get_token!(token_id), do: TokenRepository.get_token!(token_id)

  @spec get_token(binary()) :: {:ok, Token.t()} | {:error, atom()}
  def get_token(token_id), do: TokenRepository.get_token(token_id)

  @doc """
  Activates a token for a user.

  If no tokens are available, releases and reactivates the oldest active token.

  Returns `{:ok, %{token: token, token_usage: usage}}` on success,
  or `{:error, reason}` on failure.
  """
  def activate_token(user_id) do
    TokenRepository.transaction(fn ->
      with nil <- TokenRepository.get_user_active_token(user_id),
           token when not is_nil(token) <- TokenRepository.get_available_token() do
        activate_available_token(token, user_id)
      else
        _active_token = %Token{} -> {:error, :already_has_active_token}
        nil -> handle_no_available_tokens(user_id)
      end
    end)
    |> unwrap_transaction_result()
  end

  defp handle_no_available_tokens(user_id) do
    with active_count <- TokenRepository.count_active_tokens(),
         true <- active_count >= 100 do
      {:error, :no_tokens_available}
    else
      false ->
        case TokenRepository.get_oldest_active_token() do
          nil ->
            {:error, :no_tokens_available}

          token ->
            release_and_activate_token(token, user_id)
        end
    end
  end

  defp release_and_activate_token(token, user_id) do
    case release_token(token) do
      {:ok, _} -> activate_available_token(token, user_id)
      {:error, _reason} = error -> error
    end
  end

  defp activate_available_token(token, user_id) do
    with {:ok, activated_token} <- do_activate_token(token, user_id),
         {:ok, token_usage} <- create_token_usage(activated_token, user_id),
         {:ok, _job} <- schedule_cleanup(activated_token.id) do
      TokenStateManager.mark_token_active(token.id, user_id)
      {:ok, %{token: activated_token, token_usage: token_usage}}
    else
      {:error, _error} = error -> error
    end
  end

  @doc """
  Releases a token, making it available for other users.

  Closes the active usage record and schedules cleanup.

  Returns `{:ok, token}` on success, or `{:error, reason}` on failure.
  """
  def release_token(token) do
    TokenRepository.transaction(fn ->
      with {:ok, _} <- close_token_usage(token),
           {:ok, released_token} <- do_release_token(token) do
        {:ok, released_token}
      else
        error -> error
      end
    end)
    |> unwrap_transaction_result()
  end

  defp do_activate_token(token, user_id) do
    token
    |> Token.activate(user_id)
    |> TokenRepository.update()
  end

  defp create_token_usage(token, user_id) do
    token.id
    |> TokenUsage.create(user_id)
    |> TokenRepository.create_usage()
  end

  defp do_release_token(token) do
    token
    |> Token.release()
    |> TokenRepository.update()
  end

  defp close_token_usage(token) do
    case TokenRepository.get_active_usage(token.id) do
      nil ->
        {:ok, nil}

      usage ->
        usage
        |> TokenUsage.end_usage()
        |> TokenRepository.update_usage()
    end
  end

  defp schedule_cleanup(token_id) do
    TokenCleanupWorker.schedule_cleanup(token_id)
  end

  @doc """
  Releases all active tokens and closes their usage records.

  Returns `{:ok, count}` where count is the number of tokens released,
  or `{:error, reason}` on failure.
  """
  @spec clear_active_tokens() :: {:ok, non_neg_integer()} | {:error, error_reason()}
  def clear_active_tokens do
    TokenRepository.transaction(fn ->
      with {:ok, count} <- TokenRepository.clear_active_tokens(),
           {:ok, _} <- TokenRepository.close_all_active_usages() do
        TokenStateManager.clear_active_tokens()
        {:ok, count}
      end
    end)
    |> unwrap_transaction_result()
  end

  @spec list_tokens() :: [Token.t()]
  def list_tokens do
    TokenRepository.list_tokens()
  end

  defp unwrap_transaction_result({:ok, {:ok, result}}), do: {:ok, result}

  defp unwrap_transaction_result({:ok, {:error, %Ecto.Changeset{} = _changeset}}),
    do: {:error, :database_error}

  defp unwrap_transaction_result({:ok, {:error, _} = error}), do: error

  defp unwrap_transaction_result({:ok, result}), do: {:ok, result}
end
