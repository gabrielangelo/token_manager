defmodule TokenManager.Infrastructure.StateManager.TokenState do
  @moduledoc """
  Handles token state transitions and validates state changes.
  Encapsulates the logic for token state mutations while ensuring data consistency.
  """

  alias TokenManager.Domain.Token

  @type state_change :: {:token_activated, binary(), binary()} | {:token_released, binary(), nil}
  @type status :: :available | :active

  @spec transition_to_active(Token.t(), binary()) :: Token.t()
  def transition_to_active(token, user_id) do
    %{token | status: :active, current_user_id: user_id, activated_at: DateTime.utc_now()}
  end

  @spec transition_to_available(Token.t()) :: Token.t()
  def transition_to_available(token) do
    %{token | status: :available, current_user_id: nil, activated_at: nil}
  end

  @spec status_from_event(atom()) :: status()
  def status_from_event(:token_activated), do: :active
  def status_from_event(:token_released), do: :available
end
