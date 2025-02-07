defmodule TokenManager.Domain.Token.TokenUsage do
  @moduledoc """
  Domain entity for tracking individual token usage sessions, including temporal
  boundaries and user attribution. Manages the lifecycle of usage periods from
  start to completion.
  """

  defstruct [:id, :token_id, :user_id, :started_at, :ended_at]

  @type t :: %__MODULE__{
          token_id: binary(),
          user_id: binary(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil
        }

  @doc """
  Creates a new token usage record with started_at timestamp.
  """
  @spec create(binary(), binary()) :: t()
  def create(token_id, user_id) do
    %__MODULE__{
      token_id: token_id,
      user_id: user_id,
      started_at: DateTime.utc_now(),
      ended_at: nil
    }
  end

  @doc """
  Marks usage as complete by setting ended_at timestamp.
  """
  @spec end_usage(t()) :: t()
  def end_usage(token_usage) do
    %{token_usage | ended_at: DateTime.utc_now()}
  end
end
