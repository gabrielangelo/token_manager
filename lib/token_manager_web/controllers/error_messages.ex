defmodule TokenManagerWeb.ErrorMessages do
  @spec error_message(atom()) :: String.t()
  def error_message(:no_tokens_available), do: "No tokens available"
  def error_message(:already_has_active_token), do: "User already has an active token"
  def error_message(:invalid_token_state), do: "Invalid token state"
  def error_message(:token_not_found), do: "Token not found"

  def error_message(_), do: "Something went wrong"
end
