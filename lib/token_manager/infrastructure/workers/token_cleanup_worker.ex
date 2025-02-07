defmodule TokenManager.Infrastructure.Workers.TokenCleanupWorker do
  use Oban.Worker,
    queue: :tokens,
    unique: [
      fields: [:args, :worker],
      keys: [:token_id]
    ],
    max_attempts: 3

  alias TokenManager.Domain.Token.TokenService
  alias TokenManager.Infrastructure.StateManager.TokenStateManager

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"token_id" => token_id}}) do
    case TokenService.release_token_if_expired(token_id) do
      {:ok, _token} ->
        TokenStateManager.mark_token_available(token_id)
        :ok

      {:error, :token_not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def schedule_cleanup(token_id) do
    %{token_id: token_id}
    |> new(schedule_in: {2, :minutes})
    |> Oban.insert()
  end
end
