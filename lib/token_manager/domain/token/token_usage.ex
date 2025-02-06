defmodule TokenManager.Domain.Token.TokenUsage do
  @moduledoc """
  TokenUsage entity representing the domain model
  """

  defstruct [:id, :token_id, :user_id, :started_at, :ended_at]

  @type t :: %__MODULE__{
          id: binary(),
          token_id: binary(),
          user_id: binary(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil
        }

  def create(token_id, user_id) do
    %__MODULE__{
      token_id: token_id,
      user_id: user_id,
      started_at: DateTime.utc_now(),
      ended_at: nil
    }
  end

  def end_usage(token_usage) do
    %{token_usage | ended_at: DateTime.utc_now()}
  end
end
