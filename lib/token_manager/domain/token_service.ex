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
  alias TokenManager.Infrastructure.Workers.TokenCleanupWorker

  @doc """
  Retrieves a token by its ID.

  Raises if token is not found.
  """
  def get_token!(token_id), do: TokenRepository.get_token!(token_id)

  @doc """
  Activates a token for a user.

  If no tokens are available, releases and reactivates the oldest active token.

  Returns `{:ok, %{token: token, token_usage: usage}}` on success,
  or `{:error, reason}` on failure.
  """
  def activate_token(user_id) do
    TokenRepository.transaction(fn ->
      case TokenRepository.get_available_token() do
        nil ->
          handle_no_available_tokens(user_id)

        token ->
          activate_available_token(token, user_id)
      end
    end)
    |> unwrap_transaction_result()
  end

  defp handle_no_available_tokens(user_id) do
    case TokenRepository.get_oldest_active_token() do
      nil ->
        {:error, :no_tokens_available}

      token ->
        release_and_activate_token(token, user_id)
    end
  end

  defp release_and_activate_token(token, user_id) do
    with {:ok, _} <- release_token(token),
         {:ok, result} <- activate_available_token(token, user_id) do
      {:ok, result}
    else
      error -> error
    end
  end

  defp activate_available_token(token, user_id) do
    with {:ok, activated_token} <- do_activate_token(token, user_id),
         {:ok, token_usage} <- create_token_usage(activated_token, user_id),
         {:ok, _job} <- schedule_cleanup(activated_token.id) do
      {:ok, %{token: activated_token, token_usage: token_usage}}
    else
      error -> error
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
  def clear_active_tokens do
    TokenRepository.transaction(fn ->
      with {:ok, count} <- TokenRepository.clear_active_tokens(),
           {:ok, _} <- TokenRepository.close_all_active_usages() do
        {:ok, count}
      end
    end)
    |> unwrap_transaction_result()
  end

  # Helper to unwrap transaction results
  defp unwrap_transaction_result({:ok, {:ok, result}}), do: {:ok, result}
  defp unwrap_transaction_result({:ok, result}), do: {:ok, result}
  defp unwrap_transaction_result({:error, error}), do: {:error, error}
end
