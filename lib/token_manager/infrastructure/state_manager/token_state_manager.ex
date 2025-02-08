defmodule TokenManager.Infrastructure.StateManager.TokenStateManager do
  @moduledoc """
  The TokenStateManager implements a distributed token management
  system combining state access with synchronization across nodes.
  It employs a hybrid architecture using Erlang Term Storage (ETS) for fast reads
  and Phoenix PubSub for state distribution.

  ## Core Architecture

  The system uses ETS as its primary storage, configured as a public table with protected write access.
  This provides microsecond-level read performance while ensuring write operations occur only through the
  GenServer process. State changes are immediately reflected in the local ETS table and broadcast to all
  nodes via PubSub, achieving eventual consistency across the cluster.

  State synchronization relies on a combination of immediate local updates and asynchronous broadcasts.
  The database serves as the source of truth, with periodic reconciliation ensuring long-term consistency.
  A configurable refresh interval, defaulting to five minutes, balances consistency requirements with system load.

  ## Token Lifecycle

  Tokens transition between two states: available and active. Each transition records essential metadata
  including user associations and timestamps. The GenServer process ensures atomic state changes,
  while the ETS table's concurrency controls prevent race conditions.
  Token releases occur either through explicit requests or automatic cleanup after the two-minute activation period.

  ## Error Handling

  The module implements error handling through tagged tuples, allowing callers
  to implement recovery strategies. Supervision ensures state recovery after
  node failures or network partitions. Automatic state reconciliation corrects
  inconsistencies discovered during periodic database synchronization.

  Performance and Security
  Performance optimization focuses on concurrent read access while serializing
  writes through the GenServer. The ETS table uses read_concurrency: true,
  and write operations are designed for minimal contention. Security measures
  include protected table access, validated state transitions, and resource usage monitoring.

  ## Operational Support

  For operational maintenance, the module provides debugging interfaces through debug_table_state/0
  and configurable logging. These tools enable problem diagnosis in production environments
  while maintaining system security. The implementation supports named process registration
  and configurable intervals for testing isolation.

  This implementation balances performance and reliability requirements for
  distributed token management while maintaining system consistency and operational manageability.
   Its architecture provides a foundation for future enhancements such as advanced metrics collection and adaptive refresh intervals.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias TokenManager.Domain.Token
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.Repositories.TokenRepository

  @type lookup_result :: {:ok, Token.t()} | {:error, :not_found | :invalid_state}
  @type update_result :: {:ok, Token.t()} | {:error, :not_found | :update_failed}
  @type state :: %{table: :ets.tid()}

  @pubsub TokenManager.PubSub
  @topic "token_states"
  @table :token_states
  @refresh_interval :timer.minutes(5)

  @doc """
  Starts the TokenStateManager process with the given options.

  Options:
  - :name - The name to register the process under (default: __MODULE__)
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Starts the TokenStateManager process linked to the current process.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Adds a list of tokens to the state manager.
  The tokens will be converted to their domain representation before storage.
  """
  @spec add_tokens([TokenSchema.t()]) :: :ok
  def add_tokens(tokens) when is_list(tokens) do
    GenServer.call(__MODULE__, {:add_tokens, tokens})
  end

  @doc """
  Retrieves the current state of a specific token.
  Returns {:ok, token} if found, {:error, reason} otherwise.
  """
  @spec get_token_state(binary()) :: lookup_result()
  def get_token_state(token_id) when is_binary(token_id) do
    case :ets.lookup(@table, token_id) do
      [{^token_id, token}] -> {:ok, token}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns a sorted list of all available tokens.
  Tokens are sorted by activation time in descending order.
  """
  @spec get_available_tokens() :: [Token.t()]
  def get_available_tokens do
    select_and_sort_tokens(:available)
  end

  @doc """
  Returns a sorted list of all active tokens.
  Tokens are sorted by activation time in descending order.
  """
  @spec get_active_tokens() :: [Token.t()]
  def get_active_tokens do
    select_and_sort_tokens(:active)
  end

  @doc """
  Marks a token as active and assigns it to a user.
  Broadcasts the state change to all nodes.
  """
  @spec mark_token_active(Token.t(), binary()) :: update_result()
  def mark_token_active(token, user_id) do
    GenServer.call(__MODULE__, {:mark_active, token, user_id})
  end

  @doc """
  Marks a token as available, removing its user assignment.
  Broadcasts the state change to all nodes.
  """
  @spec mark_token_available(binary()) :: update_result()
  def mark_token_available(token_id) when is_binary(token_id) do
    GenServer.call(__MODULE__, {:mark_available, token_id})
  end

  @doc """
  Clears all active tokens, transitioning them to available state.
  Returns the number of tokens cleared.
  """
  @spec clear_active_tokens() :: {:ok, non_neg_integer()} | {:error, atom()}
  def clear_active_tokens do
    GenServer.call(__MODULE__, :clear_active_tokens)
  end

  @doc """
  Forces a reload of all token states from the database.
  """
  @spec reload_state() :: {:ok, non_neg_integer()}
  def reload_state do
    GenServer.call(__MODULE__, :reload_state)
  end

  @doc """
  Returns debugging information about the current state.
  """
  @spec debug_table_state() :: map()
  def debug_table_state do
    all_tokens = :ets.tab2list(@table)

    %{
      total_count: length(all_tokens),
      active_count: count_tokens_by_status(all_tokens, :active),
      available_count: count_tokens_by_status(all_tokens, :available)
    }
  end

  @doc """
  Subscribes to state changes for a specific token.
  """
  @spec subscribe_to_token(binary()) :: :ok | {:error, term()}
  def subscribe_to_token(token_id) when is_binary(token_id) do
    PubSub.subscribe(@pubsub, "token:#{token_id}")
  end

  @doc """
  Subscribes to state changes for all tokens.
  """
  @spec subscribe_to_all_tokens() :: :ok | {:error, term()}
  def subscribe_to_all_tokens do
    PubSub.subscribe(@pubsub, @topic)
  end

  @impl true
  def init(_) do
    table = initialize_table()
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
    add_tokens_to_table(tokens)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:mark_active, token, token_usage}, _from, state) do
    result = update_token_state_with_usage(token, token_usage)

    if match?({:ok, _}, result),
      do: broadcast_state_change({:token_activated, token, token_usage})

    {:reply, result, state}
  end

  @impl true
  def handle_call({:mark_available, token_id}, _from, state) do
    result = update_token_state(token_id, :available, nil)
    if match?({:ok, _}, result), do: broadcast_state_change({:token_released, token_id, nil})
    {:reply, result, state}
  end

  @impl true
  def handle_call(:clear_active_tokens, _from, state) do
    case clear_all_active_tokens() do
      {:ok, count} -> {:reply, {:ok, count}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
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

  defp initialize_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :named_table,
          :public,
          :protected,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ets.delete_all_objects(@table)
        @table
    end
  end

  defp select_and_sort_tokens(status) do
    match_spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :status, :"$2"}, status}], [:"$2"]}]

    :ets.select(@table, match_spec)
    |> Enum.sort_by(&(&1.activated_at || DateTime.from_unix!(0)), {:desc, DateTime})
  end

  defp count_tokens_by_status(tokens, status) do
    Enum.count(tokens, fn {_, token} -> token.status == status end)
  end

  defp add_tokens_to_table(tokens) do
    Enum.each(tokens, fn token ->
      domain_token = TokenSchema.to_domain(token)
      :ets.insert(@table, {token.id, domain_token})
    end)

    Logger.info("Added #{length(tokens)} new tokens to state manager")
  end

  defp clear_all_active_tokens do
    try do
      match_spec = [
        {{:"$1", :"$2"}, [{:==, {:map_get, :status, :"$2"}, :active}], [{{:"$1", :"$2"}}]}
      ]

      active_tokens = :ets.select(@table, match_spec)

      Enum.each(active_tokens, fn {token_id, token} ->
        updated_token = %{token | status: :available, current_user_id: nil, activated_at: nil}
        :ets.update_element(@table, token_id, [{2, updated_token}])
        broadcast_state_change({:token_released, token_id, nil})
      end)

      {:ok, length(active_tokens)}
    catch
      error ->
        Logger.error("Failed to clear active tokens: #{inspect(error)}")
        {:error, :clear_failed}
    end
  end

  defp update_token_state(token_id, status, user_id) do
    with [{^token_id, token}] <- :ets.lookup(@table, token_id),
         updated_token <- create_updated_token(token, status, user_id),
         true <- :ets.insert(@table, {token_id, updated_token}) do
      {:ok, updated_token}
    else
      [] ->
        {:error, :not_found}

      error ->
        Logger.error("Failed to update token state: #{inspect(error)}")
        {:error, :update_failed}
    end
  end

  defp update_token_state_with_usage(token, user_id) do
    try do
      case :ets.lookup(@table, token.id) do
        [{token_id, existing_token}] ->
          updated_token = %{
            existing_token
            | status: :active,
              activated_at: DateTime.utc_now(),
              current_user_id: user_id,
              token_usages: token.token_usages
          }

          :ets.insert(@table, {token_id, updated_token})
          {:ok, updated_token}

        [] ->
          {:error, :not_found}
      end
    catch
      error ->
        Logger.error("Failed to update token state with usage: #{inspect(error)}")
        {:error, :update_failed}
    end
  end

  defp create_updated_token(token, status, user_id) do
    %{
      token
      | status: status,
        current_user_id: user_id,
        activated_at: nil
    }
  end

  defp broadcast_state_change({event, token_id, user_id}) when event in [:token_released] do
    status = :available

    PubSub.broadcast(@pubsub, @topic, {:token_state_change, {event, token_id, user_id}})

    PubSub.broadcast(
      @pubsub,
      "token:#{token_id}",
      {:token_state_changed, token_id, status, user_id}
    )
  end

  defp broadcast_state_change({:token_activated, token, token_usage}) do
    status = :active

    PubSub.broadcast(
      @pubsub,
      @topic,
      {:token_state_change, {:token_activated, token.id, token.current_user_id, token_usage}}
    )

    PubSub.broadcast(
      @pubsub,
      "token:#{token.id}",
      {:token_state_changed, token.id, status, token.current_user_id, token_usage}
    )
  end

  defp handle_state_change({:token_activated, token_id, user_id, token_usage})
       when is_binary(token_id) do
    with {:ok, token} <- get_token_state(token_id) do
      update_token_state_with_usage(%{token | current_user_id: user_id}, token_usage)
    end
  end

  defp handle_state_change({:token_released, token_id, _user_id}) do
    update_token_state(token_id, :available, nil)
  end

  defp load_initial_state(table) do
    tokens = TokenRepository.list_tokens()
    :ets.delete_all_objects(table)
    Enum.each(tokens, &:ets.insert(table, {&1.id, &1}))
    length(tokens)
  end

  defp schedule_state_refresh do
    Process.send_after(self(), :refresh_state, @refresh_interval)
  end
end
