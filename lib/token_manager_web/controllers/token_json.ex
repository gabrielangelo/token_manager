defmodule TokenManagerWeb.TokenJSON do
  def token_activated(%{token: token, token_usage: usage}) do
    %{
      data: %{
        token_id: token.id,
        user_id: usage.user_id,
        activated_at: usage.started_at
      }
    }
  end

  def index(%{tokens: tokens}) do
    %{
      data: for(token <- tokens, do: data(token))
    }
  end

  def show(%{token: token}) do
    %{data: data_with_active_usage(token)}
  end

  def history(%{token: token}) do
    %{
      data: %{
        token_id: token.id,
        usages: Enum.map(token.token_usages, &usage_data/1)
      }
    }
  end

  def cleared(%{count: count}) do
    %{
      data: %{
        cleared_tokens: count
      }
    }
  end

  defp data(token) do
    %{
      id: token.id,
      status: token.status,
      current_user_id: Map.get(token, :current_user_id),
      activated_at: token.activated_at
    }
  end

  defp usage_data(nil), do: %{}

  defp usage_data(usage) do
    %{
      user_id: Map.get(usage, :user_id),
      started_at: usage.started_at,
      ended_at: usage.ended_at
    }
  end

  defp data_with_active_usage(token) do
    active_usage = Enum.find(token.token_usages, &usage_data/1)

    token
    |> data()
    |> Map.put(:active_usage, usage_data(active_usage))
  end
end
