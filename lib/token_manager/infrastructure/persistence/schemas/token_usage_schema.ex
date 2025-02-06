defmodule TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema do
  @moduledoc """
  Schema for token_usages table
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias TokenManager.Domain.Token.TokenUsage

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "token_usages" do
    field :user_id, :binary_id
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :token, TokenManager.Infrastructure.Persistence.Schemas.TokenSchema, type: :binary_id

    timestamps()
  end

  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:user_id, :token_id, :started_at, :ended_at])
    |> validate_required([:user_id, :token_id, :started_at])
    |> foreign_key_constraint(:token_id)
  end


  def to_domain(%__MODULE__{} = schema) do
    %TokenUsage{
      id: schema.id,
      token_id: schema.token_id,
      user_id: schema.user_id,
      started_at: schema.started_at,
      ended_at: schema.ended_at
    }
  end

  def from_domain(%TokenUsage{} = usage) do
    %__MODULE__{
      id: usage.id,
      token_id: usage.token_id,
      user_id: usage.user_id,
      started_at: usage.started_at,
      ended_at: usage.ended_at
    }
  end
end
