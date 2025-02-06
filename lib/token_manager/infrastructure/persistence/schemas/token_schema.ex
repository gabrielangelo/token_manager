defmodule TokenManager.Infrastructure.Persistence.Schemas.TokenSchema do
  @moduledoc """
  Schema for tokens table
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias TokenManager.Domain.Token
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tokens" do
    field :status, Ecto.Enum, values: [:available, :active], default: :available
    field :current_user_id, :binary_id
    field :activated_at, :utc_datetime

    has_many :token_usages, TokenUsageSchema, foreign_key: :token_id

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:status, :current_user_id, :activated_at])
    |> validate_required([:status])
  end

  def to_domain(%__MODULE__{} = schema) do
    %Token{
      id: schema.id,
      status: schema.status,
      current_user_id: schema.current_user_id,
      activated_at: schema.activated_at,
      token_usages: load_token_usages(schema.token_usages)
    }
  end

  defp load_token_usages(%Ecto.Association.NotLoaded{}), do: []

  defp load_token_usages(token_usages) when is_list(token_usages) do
    Enum.map(
      token_usages,
      & TokenUsageSchema.to_domain/1
    )
  end

  def from_domain(%Token{} = token) do
    %__MODULE__{
      id: token.id,
      status: token.status,
      current_user_id: token.current_user_id,
      activated_at: token.activated_at
    }
  end
end
