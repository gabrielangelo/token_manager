defmodule TokenManager.Domain.Token do
  @moduledoc """
  Token entity representing the domain model
  """

  defstruct [:id, :status, :current_user_id, :activated_at, :token_usages]

  @type t :: %__MODULE__{
          id: binary(),
          status: :available | :active,
          current_user_id: binary() | nil,
          activated_at: DateTime.t() | nil,
          token_usages: list()
        }

  def create() do
    %__MODULE__{
      status: :available,
      current_user_id: nil,
      activated_at: nil,
      token_usages: []
    }
  end

  def activate(token, user_id) do
    %{token | status: :active, current_user_id: user_id, activated_at: DateTime.utc_now()}
  end

  def release(token) do
    %{token | status: :available, current_user_id: nil, activated_at: nil}
  end

  def active?(token), do: token.status == :active
  def available?(token), do: token.status == :available
end
