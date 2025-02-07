# lib/token_manager_web/controllers/token_controller.ex
# Changed from TokenManager.TokenController
defmodule TokenManagerWeb.TokenController do
  use TokenManagerWeb, :controller

  alias TokenManager.Domain.Token.TokenService
  alias TokenManagerWeb.ErrorMessages

  action_fallback TokenManagerWeb.FallbackController

  @doc """
  Activates a token for the given user.

  Returns 200 with token and usage info on success.
  Returns 422 with error reason on failure.
  """
  def activate(conn, %{"user_id" => user_id}) do
    case TokenService.activate_token(user_id) do
      {:ok, %{token: token, token_usage: usage}} ->
        conn
        |> put_status(:ok)
        |> render(:token_activated, token: token, token_usage: usage)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: TokenManagerWeb.ErrorJSON)
        |> render(:error, status: 422, reason: ErrorMessages.error_message(reason))
    end
  end

  @doc """
  Lists all tokens with their current status.

  Returns 200 with list of tokens.
  """
  def index(conn, _params) do
    tokens = TokenService.list_tokens()
    # Changed from "index.json"
    render(conn, :index, tokens: tokens)
  end

  @doc """
  Gets details for a specific token including current usage.

  Returns 200 with token details on success.
  Returns 404 if token not found.
  """
  def show(conn, %{"id" => token_id}) do
    case TokenService.get_token(token_id) do
      {:ok, token} ->
        render(conn, :show, token: token)

      {:error, reason} ->
        conn
        |> put_status(:not_found)
        |> put_view(json: TokenManagerWeb.ErrorJSON)
        |> render(:error, status: 404, reason: ErrorMessages.error_message(reason))
    end

    # Changed from "show.json"
  end

  @doc """
  Gets usage history for a specific token.

  Returns 200 with list of historical usages.
  Returns 404 if token not found.
  """
  def history(conn, %{"id" => token_id}) do
    token = TokenService.get_token!(token_id)
    # Changed from "history.json"
    render(conn, :history, token: token)
  end

  @doc """
  Clears all active tokens in the system.

  Returns 200 with count of cleared tokens on success.
  Returns 422 with error reason on failure.
  """
  def clear_active(conn, _params) do
    with {:ok, count} <- TokenService.clear_active_tokens() do
      conn
      |> put_status(:ok)
      |> render(:cleared, count: count)
    end
  end
end
