defmodule TokenManagerWeb.FallbackController do
  use TokenManagerWeb, :controller

  def call(conn, {:ok, {:error, reason}}) do
    call(conn, {:error, reason})
  end

  def call(conn, {:error, :token_not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: TokenManagerWeb.ErrorJSON)
    |> render(:error, status: 404)
  end

  def call(conn, {:error, :already_has_active_token}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: TokenManagerWeb.ErrorJSON)
    |> render(:error, status: 422, reason: "User already has an active token")
  end

  def call(conn, {:error, :invalid_token_state}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: TokenManagerWeb.ErrorJSON)
    |> render(:error, status: 422, reason: "Invalid token state")
  end

  def call(conn, {:error, _}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: TokenManagerWeb.ErrorJSON)
    |> render(:error, status: 500)
  end
end
