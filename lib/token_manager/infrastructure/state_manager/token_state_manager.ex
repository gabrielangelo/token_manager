defmodule TokenManager.Infrastructure.StateManager.TokenStateManager do
  @moduledoc """
  Manages token states using ETS for concurrent access and PubSub for distribution.
  Provides a fast, concurrent way to track token states across the system while
  maintaining consistency through periodic database synchronization.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias TokenManager.Domain.Token
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.Repositories.TokenRepository

  @typedoc "Token lookup result"
  @type lookup_result :: {:ok, Token.t()} | {:error, :not_found | :invalid_state}

  @typedoc "Token update result"
  @type update_result :: {:ok, Token.t()} | {:error, :not_found | :update_failed}

  @pubsub TokenManager.PubSub
  @topic "token_states"
  @table :token_states
  @refresh_interval :timer.minutes(5)

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Adds new tokens to the ETS table.
  Called when seeding new tokens.
  """
  @spec add_tokens([TokenSchema.t()]) :: :ok
  def add_tokens(tokens) when is_list(tokens) do
    GenServer.call(__MODULE__, {:add_tokens, tokens})
  end

  @doc """
  Retrieves a token's current state from ETS.
  Provides direct concurrent access without going through GenServer.
  """
  @spec get_token_state(binary()) :: lookup_result()
  def get_token_state(token_id) when is_binary(token_id) do
    case :ets.lookup(@table, token_id) do
      [{^token_id, token}] -> {:ok, token}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns all tokens currently in available state.
  """
  @spec get_available_tokens() :: [Token.t()]
  def get_available_tokens do
    match_spec = [
      {{:"$1", :"$2"}, [{:==, {:map_get, :status, :"$2"}, :available}], [:"$2"]}
    ]

    :ets.select(@table, match_spec)
  end

  @doc """
  Returns all tokens currently in active state.
  """
  @spec get_active_tokens() :: [Token.t()]
  def get_active_tokens do
    match_spec = [
      {{:"$1", :"$2"}, [{:==, {:map_get, :status, :"$2"}, :active}], [:"$2"]}
    ]

    :ets.select(@table, match_spec)
  end

  @doc """
  Updates a token's state to active and assigns it to a user.
  Broadcasts the change to all nodes.
  """
  @spec mark_token_active(binary(), binary()) :: update_result()
  def mark_token_active(token_id, user_id) when is_binary(token_id) and is_binary(user_id) do
    GenServer.call(__MODULE__, {:mark_active, token_id, user_id})
  end

  @doc """
  Updates a token's state to available and removes user assignment.
  Broadcasts the change to all nodes.
  """
  @spec mark_token_available(binary()) :: update_result()
  def mark_token_available(token_id) when is_binary(token_id) do
    GenServer.call(__MODULE__, {:mark_available, token_id})
  end

  @doc """
  Forces a reload of the state from the database.
  Useful for manual synchronization if needed.
  """
  @spec reload_state() :: {:ok, non_neg_integer()}
  def reload_state do
    GenServer.call(__MODULE__, :reload_state)
  end

  @doc """
  Returns debug information about the current state of the ETS table.
  """
  @spec debug_table_state() :: map()
  def debug_table_state do
    all_tokens = :ets.tab2list(@table)

    %{
      total_count: length(all_tokens),
      active_count: Enum.count(all_tokens, fn {_, token} -> token.status == :active end),
      available_count: Enum.count(all_tokens, fn {_, token} -> token.status == :available end)
    }
  end

  # Server Callbacks

  @impl true
  def init(_) do
    table =
      :ets.new(@table, [
        :set,
        :named_table,
        :public,
        :protected,
        read_concurrency: true,
        write_concurrency: true
      ])

    :ok = PubSub.subscribe(@pubsub, @topic)

    load_initial_state(table)

    {:ok, %{table: table}, {:continue, :schedule_refresh}}
  end

  @impl true
  def handle_continue(:schedule_refresh, state) do
    schedule_state_refresh()
    {:noreply, state}
  end

  @impl true
  def handle_call({:add_tokens, tokens}, _from, state) do
    Enum.each(tokens, fn token ->
      domain_token = TokenManager.Infrastructure.Persistence.Schemas.TokenSchema.to_domain(token)
      :ets.insert(@table, {token.id, domain_token})
    end)

    Logger.info("Added #{length(tokens)} new tokens to state manager")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:mark_active, token_id, user_id}, _from, state) do
    result = update_token_state(token_id, :active, user_id)
    if match?({:ok, _}, result), do: broadcast_state_change({:token_activated, token_id, user_id})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:mark_available, token_id}, _from, state) do
    result = update_token_state(token_id, :available, nil)
    if match?({:ok, _}, result), do: broadcast_state_change({:token_released, token_id})
    {:reply, result, state}
  end

  @impl true
  def handle_call(:reload_state, _from, %{table: table} = state) do
    token_count = load_initial_state(table)
    {:reply, {:ok, token_count}, state}
  end

  @impl true
  def handle_info({:token_state_change, change}, state) do
    handle_state_change(change)
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_state, state) do
    load_initial_state(state.table)
    schedule_state_refresh()
    {:noreply, state}
  end

  defp broadcast_state_change(change) do
    PubSub.broadcast(@pubsub, @topic, {:token_state_change, change})
  end

  defp handle_state_change({:token_activated, token_id, user_id}) do
    update_token_state(token_id, :active, user_id)
  end

  defp handle_state_change({:token_released, token_id}) do
    update_token_state(token_id, :available, nil)
  end

  defp update_token_state(token_id, status, user_id) do
    try do
      case :ets.lookup(@table, token_id) do
        [{^token_id, token}] ->
          updated_token = %{
            token
            | status: status,
              current_user_id: user_id,
              activated_at: if(status == :active, do: DateTime.utc_now(), else: nil)
          }

          true = :ets.insert(@table, {token_id, updated_token})
          {:ok, updated_token}

        [] ->
          {:error, :not_found}
      end
    catch
      error ->
        Logger.error("Failed to update token state: #{inspect(error)}")
        {:error, :update_failed}
    end
  end

  defp load_initial_state(table) do
    tokens = TokenRepository.list_tokens()

    :ets.delete_all_objects(table)

    tokens
    |> Enum.each(fn token ->
      :ets.insert(table, {token.id, token})
    end)

    length(tokens)
  end

  defp schedule_state_refresh do
    Process.send_after(self(), :refresh_state, @refresh_interval)
  end
end
