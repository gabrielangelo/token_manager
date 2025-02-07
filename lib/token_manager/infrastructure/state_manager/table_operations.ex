defmodule TokenManager.Infrastructure.StateManager.TableOperations do
  @moduledoc """
  Handles all ETS table operations, providing a clean interface for
  table access and modifications.
  """

  require Logger
  alias TokenManager.Domain.Token

  @table :token_states

  @spec initialize_table() :: :ets.tid()
  def initialize_table do
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

  @spec query_active_tokens() :: [{binary(), Token.t()}]
  def query_active_tokens do
    match_spec = [
      {{:"$1", :"$2"}, [{:==, {:map_get, :status, :"$2"}, :active}], [{{:"$1", :"$2"}}]}
    ]

    :ets.select(@table, match_spec)
  end

  @spec get_available_tokens() :: [Token.t()]
  def get_available_tokens do
    match_spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :status, :"$2"}, :available}], [:"$2"]}]

    :ets.select(@table, match_spec)
    |> Enum.sort_by(&(&1.activated_at || DateTime.from_unix!(0)), {:desc, DateTime})
  end

  @spec update_token(binary(), Token.t()) :: {:ok, Token.t()} | {:error, atom()}
  def update_token(token_id, updated_token) do
    case :ets.update_element(@table, token_id, [{2, updated_token}]) do
      true -> {:ok, updated_token}
      false -> {:error, :update_failed}
    end
  end
end
