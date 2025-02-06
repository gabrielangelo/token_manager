defmodule TokenManager.Domain.Token.TokenService do
  alias TokenManager.Domain.Token
  alias TokenManager.Domain.Token.TokenUsage
  alias TokenManager.Infrastructure.Repositories.TokenRepository
  alias TokenManager.Infrastructure.Workers.TokenCleanupWorker

  def get_token!(token_id), do: TokenRepository.get_token!(token_id)

  def activate_token(user_id) do
    TokenRepository.transaction(fn ->
      case TokenRepository.get_available_token()  do
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
