defmodule TokenManager.Infrastructure.Workers.TokenCleanupWorker do
  @moduledoc """
  An Oban worker that handles the periodic cleanup of expired tokens
  from the token store. Using Oban's scheduling capabilities, it runs
  at configurable intervals to maintain system health by removing tokens
  that are no longer valid.
  """
  use Oban.Worker,
    queue: :token_cleanup_queue,
    unique: [
      fields: [:args, :worker],
      keys: [:token_id]
    ],
    max_attempts: 3

  alias TokenManager.Domain.Token.TokenService

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"token_id" => token_id}}) do
    Logger.info("cleaning token #{token_id}")

    case TokenService.release_token_if_expired(token_id) do
      {:ok, _token} ->
        Logger.info("token #{token_id} succesfully released!")
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
