defmodule TokenManager.Domain.Token do
  @moduledoc """
  Core domain entity representing a token in the system. Manages token state transitions
  and associated user assignments while encapsulating business rules around token
  activation and release.
  """

  defstruct [:id, :status, :current_user_id, :activated_at, :token_usages]

  @type t :: %__MODULE__{
          id: binary(),
          status: :available | :active,
          current_user_id: binary() | nil,
          activated_at: DateTime.t() | nil,
          token_usages: list()
        }

  @doc """
  Creates a new token with initial available state.
  """
  @spec create :: t()
  def create do
    %__MODULE__{
      status: :available,
      current_user_id: nil,
      activated_at: nil,
      token_usages: []
    }
  end

  @doc """
  Activates a token for a user, setting status and recording activation time.
  """
  @spec activate(t(), binary()) :: t()
  def activate(token, user_id) do
    %{token | status: :active, current_user_id: user_id, activated_at: DateTime.utc_now()}
  end

  @doc """
  Releases a token, clearing user assignment and activation data.
  """
  @spec release(t()) :: t()
  def release(token) do
    %{token | status: :available, current_user_id: nil, activated_at: nil}
  end

  @doc """
  Checks if token is in active state.
  """
  @spec active?(t()) :: boolean()
  def active?(token), do: token.status == :active

  @doc """
  Checks if token is in available state.
  """
  @spec available?(t()) :: boolean()
  def available?(token), do: token.status == :available
end
