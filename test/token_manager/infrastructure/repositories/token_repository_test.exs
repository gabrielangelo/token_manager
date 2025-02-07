defmodule TokenManager.Infrastructure.Repositories.TokenRepositoryTest do
  use TokenManager.DataCase

  alias TokenManager.Domain.Token.TokenUsage
  alias TokenManager.Infrastructure.Repositories.TokenRepository

  import TokenManager.Factory

  describe "count_total_tokens/0" do
    test "returns correct count of total tokens" do
      insert_list(3, :token_schema)
      assert TokenRepository.count_total_tokens() == 3
    end
  end

  describe "count_active_tokens/0" do
    test "returns correct count of active tokens" do
      insert_list(2, :active_token_schema)
      insert(:token_schema)
      assert TokenRepository.count_active_tokens() == 2
    end
  end

  describe "count_active_usages/0" do
    test "returns correct count of active usages" do
      token = insert(:token_schema)
      insert(:token_usage_schema, token_id: token.id)
      insert(:token_usage_schema, token_id: token.id, ended_at: DateTime.utc_now())

      assert TokenRepository.count_active_usages() == 1
    end
  end

  describe "get_token_history/1" do
    test "returns all usages for a token in descending order" do
      token = insert(:token_schema)
      now = DateTime.utc_now()

      usage1 =
        insert(:token_usage_schema,
          token_id: token.id,
          started_at: DateTime.add(now, -2, :hour),
          ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      usage2 =
        insert(:token_usage_schema,
          token_id: token.id,
          started_at: DateTime.add(now, -1, :hour),
          ended_at:
            DateTime.utc_now()
            |> DateTime.truncate(:second)
        )

      [second, first] = TokenRepository.get_token_history(token.id)

      assert first.id == usage2.id
      assert second.id == usage1.id
    end

    test "returns empty list for token with no history" do
      token = insert(:token_schema)
      assert TokenRepository.get_token_history(token.id) == []
    end
  end

  describe "get_token!/1" do
    test "returns token with preloaded usages" do
      token = insert(:token_schema)
      usage = insert(:token_usage_schema, token_id: token.id)

      fetched_token = TokenRepository.get_token!(token.id)

      assert fetched_token.id == token.id
      assert length(fetched_token.token_usages) == 1
      assert hd(fetched_token.token_usages).id == usage.id
    end
  end

  describe "get_available_token/0" do
    test "returns an available token" do
      available_token = insert(:token_schema)
      insert(:active_token_schema)

      fetched_token = TokenRepository.get_available_token()
      assert fetched_token.id == available_token.id
    end

    test "returns nil when no available tokens exist" do
      insert(:active_token_schema)
      assert TokenRepository.get_available_token() == nil
    end
  end

  describe "get_oldest_active_token/0" do
    test "returns the oldest active token based on activation time" do
      now = DateTime.utc_now()

      oldest = insert(:active_token_schema, activated_at: DateTime.add(now, -2, :hour))
      _newer = insert(:active_token_schema, activated_at: DateTime.add(now, -1, :hour))

      fetched_token = TokenRepository.get_oldest_active_token()
      assert fetched_token.id == oldest.id
    end

    test "returns nil when no active tokens exist" do
      insert(:token_schema)
      assert TokenRepository.get_oldest_active_token() == nil
    end
  end

  describe "update/1" do
    test "updates token attributes" do
      token = insert(:token_schema)
      user_id = Ecto.UUID.generate()

      {:ok, updated_token} =
        TokenRepository.update(%{
          token
          | status: :active,
            current_user_id: user_id,
            activated_at: DateTime.utc_now()
        })

      assert updated_token.status == :active
      assert updated_token.current_user_id == user_id
      assert not is_nil(updated_token.activated_at)
    end
  end

  describe "create_usage/1" do
    test "creates token usage record" do
      token = insert(:token_schema)
      user_id = Ecto.UUID.generate()
      started_at = DateTime.utc_now()

      {:ok, usage} =
        TokenRepository.create_usage(%TokenUsage{
          token_id: token.id,
          user_id: user_id,
          started_at: started_at
        })

      assert usage.token_id == token.id
      assert usage.user_id == user_id
    end
  end

  describe "get_active_usage/1" do
    test "returns active usage for token" do
      token = insert(:token_schema)
      usage = insert(:token_usage_schema, token_id: token.id)
      insert(:token_usage_schema, token_id: token.id, ended_at: DateTime.utc_now())

      fetched_usage = TokenRepository.get_active_usage(token.id)
      assert fetched_usage.id == usage.id
    end

    test "returns nil when no active usage exists" do
      token = insert(:token_schema)
      insert(:token_usage_schema, token_id: token.id, ended_at: DateTime.utc_now())

      assert TokenRepository.get_active_usage(token.id) == nil
    end
  end

  describe "clear_active_tokens/0" do
    test "clears all active tokens" do
      insert_list(3, :active_token_schema)
      insert(:token_schema)

      {:ok, count} = TokenRepository.clear_active_tokens()

      assert count == 3
      assert TokenRepository.count_active_tokens() == 0
    end
  end

  describe "close_all_active_usages/0" do
    test "closes all active usages" do
      token = insert(:token_schema)
      insert_list(2, :token_usage_schema, token_id: token.id)
      insert(:token_usage_schema, token_id: token.id, ended_at: DateTime.utc_now())

      {:ok, count} = TokenRepository.close_all_active_usages()

      assert count == 2
      assert TokenRepository.count_active_usages() == 0
    end
  end

  describe "transaction/1" do
    test "executes transaction successfully" do
      result = TokenRepository.transaction(fn -> {:ok, :success} end)
      assert result == {:ok, {:ok, :success}}
    end

    test "rolls back transaction on error" do
      result = TokenRepository.transaction(fn -> {:error, :failure} end)
      assert result == {:ok, {:error, :failure}}
    end
  end
end
