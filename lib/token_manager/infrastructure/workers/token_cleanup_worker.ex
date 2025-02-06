defmodule TokenManager.Infrastructure.Workers.TokenCleanupWorker do
  @moduledoc """
  Worker for cleaning up expired tokens
  """

  use Oban.Worker, queue: :tokens

  alias TokenManager.Domain.Token.TokenService

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args["token_id"]
    |> TokenManager.Infrastructure.Repositories.TokenRepository.get_token!()
    |> TokenService.release_token()

    :ok
  end

  def schedule_cleanup(token_id) do
    %{token_id: token_id}
    |> new(schedule_in: 120)
    |> Oban.insert()
  end
end
