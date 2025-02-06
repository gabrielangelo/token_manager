defmodule TokenManager.Infrastructure.Persistence.Schemas.TokenSchema do
  @moduledoc """
  Defines the database schema for tokens, managing their lifecycle states and user assignments.
  Enforces uniqueness constraints to prevent duplicate active tokens per user and handles
  token ownership transitions with associated usage tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias TokenManager.Domain.Token
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
    id: binary(),
    status: :available | :active,
    current_user_id: binary() | nil,
    activated_at: DateTime.t() | nil,
    token_usages: [TokenUsageSchema.t()] | Ecto.Association.NotLoaded.t(),
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  schema "tokens" do
    field :status, Ecto.Enum, values: [:available, :active], default: :available
    field :current_user_id, :binary_id
    field :activated_at, :utc_datetime

    has_many :token_usages, TokenUsageSchema, foreign_key: :token_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for token updates with validation rules.

  Required: status
  Optional: current_user_id, activated_at

  Enforces unique constraint preventing multiple active tokens per user.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:status, :current_user_id, :activated_at])
    |> validate_required([:status])
    |> unique_constraint(:current_user_id,
      name: :unique_active_user_token_index,
      message: "user already has an active token"
    )
  end

  @doc """
  Converts schema struct to domain entity, handling association loading.
  """
  @spec to_domain(%__MODULE__{}) :: Token.t()
  def to_domain(%__MODULE__{} = schema) do
    %Token{
      id: schema.id,
      status: schema.status,
      current_user_id: schema.current_user_id,
      activated_at: schema.activated_at,
      token_usages: load_token_usages(schema.token_usages)
    }
  end

  @doc """
  Converts domain entity to schema struct.
  """
  @spec from_domain(Token.t()) :: t()
  def from_domain(%Token{} = token) do
    %__MODULE__{
      id: token.id,
      status: token.status,
      current_user_id: token.current_user_id,
      activated_at: token.activated_at
    }
  end

  defp load_token_usages(%Ecto.Association.NotLoaded{}), do: []
  defp load_token_usages(token_usages) when is_list(token_usages) do
    Enum.map(token_usages, &TokenUsageSchema.to_domain/1)
  end
end
