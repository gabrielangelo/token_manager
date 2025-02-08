defmodule TokenManager.Infrastructure.StateManager.TokenStateManagerTest do
  use TokenManager.DataCase
  alias TokenManager.Domain.Token.TokenService

  alias TokenManager.Infrastructure.StateManager.TokenStateManager

  alias Phoenix.PubSub

  @pubsub TokenManager.PubSub

  setup do
    on_exit(fn ->
      :ets.delete_all_objects(:token_states)
    end)

    :ok
  end

  describe "mark_token_active/2" do
    test "publishes token activation event" do
      user_id = Ecto.UUID.generate()
      token = build(:token_schema, status: :available)
      TokenStateManager.add_tokens([token])

      PubSub.subscribe(@pubsub, "token:#{token.id}")
      TokenStateManager.mark_token_active(token, user_id)
      token_id = token.id
      assert_receive {:token_state_changed, ^token_id, :active, nil, ^user_id}
    end
  end

  describe "mark_token_available/1" do
    test "publishes token available event" do
      token = insert(:token_schema, status: :active)
      TokenStateManager.add_tokens([token])

      PubSub.subscribe(@pubsub, "token:#{token.id}")
      TokenStateManager.mark_token_available(token.id)
      token_id = token.id

      assert_receive {:token_state_changed, ^token_id, :available, nil}
    end
  end

  describe "subscribe_to_token/1" do
    test "receives events for specific token" do
      user_id = Ecto.UUID.generate()
      token = build(:token_schema, status: :available)
      TokenStateManager.add_tokens([token])

      TokenStateManager.subscribe_to_token(token.id)
      TokenStateManager.mark_token_active(token, user_id)
      token_id = token.id

      assert_receive {:token_state_changed, ^token_id, :active, nil, ^user_id}
    end

    test "doesn't receive events for other tokens" do
      user_id = Ecto.UUID.generate()
      token = build(:token_schema, status: :available)
      other_token = insert(:token_schema, status: :available)
      TokenStateManager.add_tokens([token, other_token])

      TokenStateManager.subscribe_to_token(token.id)
      TokenStateManager.mark_token_active(other_token, user_id)

      refute_receive {:token_state_changed, _, _, _}
    end
  end

  describe "subscribe_to_all_tokens/0" do
    test "receives events for all tokens" do
      user_id = Ecto.UUID.generate()
      insert(:token_schema, status: :available)

      [token] =
        created_tokens =
        TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
        |> Repo.all()
        |> Repo.preload(:token_usages)

      TokenStateManager.subscribe_to_all_tokens()
      TokenStateManager.add_tokens(created_tokens)

      TokenService.activate_token(user_id)
      token_id = token.id
      assert_receive {:token_state_change, {:token_activated, ^token_id, _, ^user_id}}
    end
  end
end
