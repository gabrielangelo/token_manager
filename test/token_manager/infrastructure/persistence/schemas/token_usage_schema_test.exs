defmodule TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchemaTest do
  use TokenManager.DataCase

  alias TokenManager.Domain.Token.TokenUsage
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema

  describe "changeset/2" do
    test "validates required fields" do
      changeset = TokenUsageSchema.changeset(%TokenUsageSchema{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).token_id
      assert "can't be blank" in errors_on(changeset).started_at
    end

    test "creates valid changeset with required fields" do
      attrs = %{
        user_id: Ecto.UUID.generate(),
        token_id: Ecto.UUID.generate(),
        started_at: DateTime.utc_now()
      }

      changeset = TokenUsageSchema.changeset(%TokenUsageSchema{}, attrs)
      assert changeset.valid?
    end
  end

  describe "to_domain/1" do
    test "converts schema to domain entity" do
      now = DateTime.utc_now()

      schema = %TokenUsageSchema{
        id: "usage-id",
        token_id: "token-id",
        user_id: "user-id",
        started_at: now,
        ended_at: now
      }

      domain = TokenUsageSchema.to_domain(schema)

      assert %TokenUsage{} = domain
      assert domain.id == "usage-id"
      assert domain.token_id == "token-id"
      assert domain.user_id == "user-id"
      assert domain.started_at == now
      assert domain.ended_at == now
    end
  end

  describe "from_domain/1" do
    test "converts domain entity to schema" do
      now = DateTime.utc_now()

      domain = %TokenUsage{
        id: "usage-id",
        token_id: "token-id",
        user_id: "user-id",
        started_at: now,
        ended_at: now
      }

      schema = TokenUsageSchema.from_domain(domain)

      assert %TokenUsageSchema{} = schema
      assert schema.id == "usage-id"
      assert schema.token_id == "token-id"
      assert schema.user_id == "user-id"
      assert schema.started_at == now
      assert schema.ended_at == now
    end
  end
end
