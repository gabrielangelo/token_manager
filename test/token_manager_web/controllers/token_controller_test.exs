defmodule TokenManagerWeb.TokenControllerTest do
  use TokenManagerWeb.ConnCase, async: false

  import TokenManager.Factory

  alias TokenManager.Infrastructure.Repositories.TokenRepository
  alias TokenManager.Infrastructure.StateManager.TokenStateManager

  setup do
    {:ok, _token_manager} =
      start_supervised({
        TokenManager.Infrastructure.StateManager.TokenStateManager,
        name: :"TokenStateManager_#{:rand.uniform(100_000)}"
      })

    :ok
  end

  describe "POST /api/tokens/activate" do
    test "successfully activates an available token", %{conn: conn} do
      insert(:token_schema, status: :available)
      user_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/tokens/activate", %{user_id: user_id})

      assert %{
               "data" => %{
                 "token_id" => _token_id,
                 "user_id" => ^user_id,
                 "activated_at" => _activated_at
               }
             } = json_response(conn, 200)
    end

    test "returns error when user already has active token", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      token = insert(:active_token_schema, current_user_id: user_id)
      insert(:token_usage_schema, token_id: token.id, user_id: user_id)

      conn = post(conn, ~p"/api/tokens/activate", %{user_id: user_id})

      assert %{"errors" => %{"detail" => "User already has an active token"}} =
               json_response(conn, 422)
    end

    test "returns error when no tokens are available", %{conn: conn} do
      user_id = Ecto.UUID.generate()

      Enum.each(1..100, fn _ ->
        other_user_id = Ecto.UUID.generate()
        token = insert(:active_token_schema, current_user_id: other_user_id)
        insert(:token_usage_schema, token_id: token.id, user_id: other_user_id)
      end)

      conn = post(conn, ~p"/api/tokens/activate", %{user_id: user_id})

      assert %{"errors" => %{"detail" => "No tokens available"}} = json_response(conn, 422)
    end
  end

  describe "GET /api/tokens" do
    test "lists all tokens from db", %{conn: conn} do
      token1 = insert(:token_schema, status: :available)
      user_id = Ecto.UUID.generate()

      token2 = insert(:token_schema, status: :active, current_user_id: user_id)
      token3 = insert(:token_schema, status: :available)

      insert(:token_usage_schema, %{
        token_id: token2.id,
        user_id: user_id,
        started_at: DateTime.utc_now()
      })

      conn = get(conn, ~p"/api/tokens")

      token1_id = token1.id
      token2_id = token2.id
      token3_id = token3.id

      assert %{
               "data" => [
                 %{"id" => ^token1_id, "status" => "available"},
                 %{"id" => ^token2_id, "status" => "active"},
                 %{"id" => ^token3_id, "status" => "available"}
               ]
             } = json_response(conn, 200)
    end

    test "lists all tokens from cache", %{conn: conn} do
      token1 = insert(:token_schema, status: :available)
      user_id = Ecto.UUID.generate()

      token2 = insert(:token_schema, status: :active, current_user_id: user_id)
      token3 = insert(:token_schema, status: :available)

      insert(:token_usage_schema, %{
        token_id: token2.id,
        user_id: user_id,
        started_at: DateTime.utc_now()
      })

      TokenStateManager.add_tokens([token1, token2, token3])
      conn = get(conn, ~p"/api/tokens")

      response = json_response(conn, 200)["data"]

      assert length(response) == 3

      assert Enum.all?(response, fn token ->
               token["id"] in [token1.id, token2.id, token3.id] &&
                 token["status"] in ["available", "active"]
             end)
    end
  end

  describe "GET /api/tokens/:id" do
    test "shows token with active usage from db", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      token = insert(:token_schema, status: :active, current_user_id: user_id)
      insert(:token_usage_schema, token_id: token.id, user_id: user_id)

      conn = get(conn, ~p"/api/tokens/#{token.id}")
      token_id = token.id

      assert %{
               "data" => %{
                 "id" => ^token_id,
                 "status" => "active",
                 "current_user_id" => ^user_id,
                 "active_usage" => %{
                   "ended_at" => nil,
                   "started_at" => _,
                   "user_id" => ^user_id
                 }
               }
             } = json_response(conn, 200)
    end

    test "shows token with active usage from cache", %{conn: conn} do
      user_id = Ecto.UUID.generate()

      token =
        build(:token_schema, id: Ecto.UUID.generate(), status: :active, current_user_id: user_id)

      usage = build(:token_usage_schema, token_id: token.id, user_id: user_id)

      token = Map.put(token, :token_usages, [usage])
      TokenStateManager.add_tokens([token])

      conn = get(conn, ~p"/api/tokens/#{token.id}")

      assert %{
               "data" => %{
                 "id" => _id,
                 "status" => "active",
                 "current_user_id" => ^user_id,
                 "active_usage" => %{
                   "ended_at" => nil,
                   "started_at" => _,
                   "user_id" => ^user_id
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns 404 for non-existent token", %{conn: conn} do
      conn = get(conn, ~p"/api/tokens/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/tokens/:id/history" do
    test "shows token usage history", %{conn: conn} do
      token = insert(:token_schema)
      user1_id = Ecto.UUID.generate()
      user2_id = Ecto.UUID.generate()

      insert(:token_usage_schema,
        token_id: token.id,
        user_id: user1_id,
        ended_at: DateTime.utc_now()
      )

      insert(:token_usage_schema, token_id: token.id, user_id: user2_id)

      conn = get(conn, ~p"/api/tokens/#{token.id}/history")
      response = json_response(conn, 200)

      assert response["data"]["token_id"] == token.id
      [last_token_usage, first_token_usage] = response["data"]["usages"]

      assert last_token_usage["user_id"] == user1_id
      assert not is_nil(last_token_usage["ended_at"])

      assert first_token_usage["user_id"] == user2_id

      assert is_nil(first_token_usage["ended_at"])
    end

    test "returns empty history for token with no usages", %{conn: conn} do
      token = insert(:token_schema)

      conn = get(conn, ~p"/api/tokens/#{token.id}/history")

      assert %{"data" => %{"token_id" => _token_id, "usages" => []}} = json_response(conn, 200)
    end
  end

  describe "POST /api/tokens/clear" do
    test "clears all active tokens", %{conn: conn} do
      Enum.each(1..3, fn _ ->
        token = insert(:token_schema, status: :active)
        insert(:token_usage_schema, token_id: token.id)
      end)

      conn = post(conn, ~p"/api/tokens/clear")

      assert %{"data" => %{"cleared_tokens" => 3}} = json_response(conn, 200)
      assert TokenRepository.count_active_tokens() == 0
    end

    test "returns success when no active tokens exist", %{conn: conn} do
      conn = post(conn, ~p"/api/tokens/clear")

      assert %{"data" => %{"cleared_tokens" => 0}} = json_response(conn, 200)
    end
  end
end
