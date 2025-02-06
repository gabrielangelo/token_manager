defmodule TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema do
  @moduledoc """
  Defines the database schema for token usage tracking, managing temporal aspects of token
  assignments including activation and release times. This schema maintains the relationship
  between tokens and users while preserving the complete history of token utilization patterns
  and ownership transitions.
  """

  use Ecto.Schema
  alias TokenManager.Domain.Token.TokenUsage
  alias TokenManager.Domain.Token.TokenUsage
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          user_id: binary(),
          token_id: binary(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type from_domain_type :: %__MODULE__{
          id: binary(),
          token_id: binary(),
          user_id: binary(),
          started_at: DateTime.t(),
          ended_at: DateTime.t()
        }

  schema "token_usages" do
    field :user_id, :binary_id
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :token, TokenSchema, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for token usage records with validation rules.

  Requires:
  - user_id: identifies the token user
  - token_id: reference to the associated token
  - started_at: timestamp when usage began

  Optional:
  - ended_at: timestamp when usage ended

  Returns `%Ecto.Changeset{}`.
  """
  @spec changeset(from_domain_type(), map()) :: Ecto.Changeset.t()
  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:user_id, :token_id, :started_at, :ended_at])
    |> validate_required([:user_id, :token_id, :started_at])
    |> foreign_key_constraint(:token_id)
  end

  @doc """
  Converts a schema struct to domain entity.

  All fields are mapped directly with no transformations.
  """
  @spec to_domain(__MODULE__.t()) :: TokenUsage.t()
  def to_domain(%__MODULE__{} = schema) do
    %TokenUsage{
      id: schema.id,
      token_id: schema.token_id,
      user_id: schema.user_id,
      started_at: schema.started_at,
      ended_at: schema.ended_at
    }
  end

  @doc """
  Converts a domain entity to schema struct.

  All fields are mapped directly with no transformations.
  """
  @spec from_domain(TokenUsage.t()) :: from_domain_type()
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
