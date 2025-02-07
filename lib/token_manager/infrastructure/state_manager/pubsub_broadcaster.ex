defmodule TokenManager.Infrastructure.StateManager.PubSubBroadcaster do
  @moduledoc """
  Handles all PubSub related operations, including broadcasting state changes
  and managing subscriptions.
  """

  alias Phoenix.PubSub
  alias TokenManager.Infrastructure.StateManager.TokenState

  @pubsub TokenManager.PubSub
  @topic "token_states"

  @spec broadcast_state_change(TokenState.state_change()) :: :ok
  def broadcast_state_change({event, token_id, user_id} = change) do
    status = TokenState.status_from_event(event)

    PubSub.broadcast(@pubsub, @topic, {:token_state_change, change})

    PubSub.broadcast(
      @pubsub,
      "token:#{token_id}",
      {:token_state_changed, token_id, status, user_id}
    )
  end

  @spec subscribe_to_token(binary()) :: :ok | {:error, term()}
  def subscribe_to_token(token_id) when is_binary(token_id) do
    PubSub.subscribe(@pubsub, "token:#{token_id}")
  end

  @spec subscribe_to_all_tokens() :: :ok | {:error, term()}
  def subscribe_to_all_tokens do
    PubSub.subscribe(@pubsub, @topic)
  end
end
