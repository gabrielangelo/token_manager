defmodule TokenManager.Domain.Token.TokenServiceTest do
  @moduledoc false
  use TokenManager.DataCase, async: false

  alias TokenManager.Infrastructure.StateManager.TokenStateManager
  use Oban.Testing, repo: TokenManager.Repo

  alias TokenManager.Domain.Token.TokenService
  alias TokenManager.Infrastructure.Repositories.TokenRepository
  alias TokenManager.Infrastructure.Workers.TokenCleanupWorker
  import TokenManager.Factory

  setup do
    {:ok, _token_manager} =
      start_supervised({
        TokenManager.Infrastructure.StateManager.TokenStateManager,
        name: :"TokenStateManager_#{:rand.uniform(100_000)}"
      })

    :ok
  end

  describe "token activation" do
    test "successfully activates an available token" do
      user_id = Ecto.UUID.generate()
      token = insert(:token_schema)

      {:ok, %{token: activated_token, token_usage: usage}} = TokenService.activate_token(user_id)

      assert activated_token.status == :active
      assert activated_token.current_user_id == user_id
      assert not is_nil(activated_token.activated_at)
      assert usage.user_id == user_id
      assert usage.token_id == token.id
      assert not is_nil(usage.started_at)
      assert is_nil(usage.ended_at)
    end

    test "releases oldest active token when limit is reached" do
      user_id = Ecto.UUID.generate()

      oldest_user_id = Ecto.UUID.generate()

      oldest_token =
        insert(:token_schema, %{
          status: :active,
          current_user_id: oldest_user_id,
          activated_at: DateTime.add(DateTime.utc_now(), -100, :second)
        })

      insert(:token_usage_schema, %{
        token_id: oldest_token.id,
        user_id: oldest_user_id,
        started_at: oldest_token.activated_at
      })

      Enum.each(1..98, fn _ ->
        token = insert(:active_token_schema)

        insert(:token_usage_schema, %{
          token_id: token.id,
          user_id: token.current_user_id,
          started_at: token.activated_at
        })
      end)

      {:ok, %{token: updated_token}} = TokenService.activate_token(user_id)
      updated_token = TokenService.get_token!(updated_token.id)

      [oldest_token_usage_track, last_token_usage_track] = updated_token.token_usages
      assert oldest_token_usage_track.user_id == oldest_user_id

      assert last_token_usage_track.user_id == user_id
      assert updated_token.current_user_id == user_id
    end

    test "prevents activating more than 100 tokens simultaneously" do
      user_id = Ecto.UUID.generate()

      Enum.each(1..100, fn _ ->
        token = insert(:active_token_schema)

        insert(:token_usage_schema, %{
          token_id: token.id,
          user_id: token.current_user_id,
          started_at: token.activated_at
        })
      end)

      assert {:error, :no_tokens_available} == TokenService.activate_token(user_id)
    end
  end

  describe "token usage tracking" do
    test "tracks token usage history" do
      user_id_1 = Ecto.UUID.generate()
      user_id_2 = Ecto.UUID.generate()

      token = insert(:token_schema)

      {:ok, %{token: activated_token}} = TokenService.activate_token(user_id_1)
      assert activated_token.status == :active

      {:ok, _} = TokenService.release_token(activated_token)

      {:ok, %{token: _}} = TokenService.activate_token(user_id_2)

      history = TokenRepository.get_token_history(token.id)
      assert length(history) == 2

      [first_usage, latest_usage] = history
      assert first_usage.user_id == user_id_1
      assert not is_nil(first_usage.ended_at)
      assert latest_usage.user_id == user_id_2
      assert is_nil(latest_usage.ended_at)
    end
  end

  describe "token cleanup" do
    test "assert that the release token job will be enqueued" do
      user_id = Ecto.UUID.generate()
      token = insert(:token_schema)

      {:ok, %{token: activated_token}} = TokenService.activate_token(user_id)

      activated_token = %{
        activated_token
        | activated_at: DateTime.add(DateTime.utc_now(), -150, :second)
      }

      {:ok, expired_token} =
        TokenRepository.update(activated_token)

      args = %{token_id: expired_token.id}

      assert_enqueued(
        worker: TokenCleanupWorker,
        args: args
      )

      [job] = TokenManager.Repo.all(Oban.Job)

      TokenCleanupWorker.perform(job)
      released_token = TokenRepository.get_token!(token.id)
      assert released_token.status == :available
      assert is_nil(released_token.current_user_id)
    end

    test "cleanup updates token usage history" do
      user_id = Ecto.UUID.generate()
      token = insert(:token_schema)

      {:ok, %{token: activated_token}} = TokenService.activate_token(user_id)

      activated_token = %{
        activated_token
        | activated_at: DateTime.add(DateTime.utc_now(), -121, :second)
      }

      {:ok, expired_token} = TokenRepository.update(activated_token)

      args = %{token_id: expired_token.id}

      assert_enqueued(
        worker: TokenCleanupWorker,
        args: args
      )

      [job] = TokenManager.Repo.all(Oban.Job)
      TokenCleanupWorker.perform(job)

      [usage] = TokenRepository.get_token_history(token.id)
      assert not is_nil(usage.ended_at)
    end
  end

  describe "token operations" do
    test "clearing active tokens" do
      tokens = insert_list(5, :token_schema)
      TokenStateManager.add_tokens(tokens)

      Enum.each(1..5, fn _ ->
        user_id = Ecto.UUID.generate()
        {:ok, _} = TokenService.activate_token(user_id)
      end)

      Enum.empty?(TokenStateManager.get_available_tokens())
      {:ok, cleared_count} = TokenService.clear_active_tokens()

      assert cleared_count == 5
      assert TokenRepository.count_active_tokens() == 0
      assert length(TokenStateManager.get_available_tokens()) == 5

      refute Enum.empty?(TokenStateManager.get_available_tokens())
      assert Enum.empty?(TokenStateManager.get_active_tokens())

      active_usages = TokenRepository.count_active_usages()
      assert active_usages == 0
    end
  end

  describe "token limits" do
    test "maintains exactly 100 total tokens" do
      insert_list(100, :token_schema)

      total_count = TokenRepository.count_total_tokens()
      assert total_count == 100

      user_id = Ecto.UUID.generate()
      {:ok, _} = TokenService.activate_token(user_id)

      assert TokenRepository.count_total_tokens() == 100
    end
  end
end
