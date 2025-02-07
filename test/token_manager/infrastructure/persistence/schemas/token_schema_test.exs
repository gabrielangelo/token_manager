defmodule TokenManager.Infrastructure.Persistence.Schemas.TokenSchemaTest do
  use TokenManager.DataCase

  alias TokenManager.Domain.Token
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema

  describe "changeset/2" do
    test "validates required fields" do
      changeset = TokenSchema.changeset(%TokenSchema{}, %{})
      assert changeset.valid?
    end

    test "validates status enum" do
      changeset = TokenSchema.changeset(%TokenSchema{}, %{status: :invalid})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "enforces unique user_id for active tokens" do
      user_id = Ecto.UUID.generate()

      insert(:token_schema, status: :active, current_user_id: user_id)

      changeset =
        TokenSchema.changeset(%TokenSchema{}, %{
          status: :active,
          current_user_id: user_id
        })

      {:error, changeset} = Repo.insert(changeset)

      assert "user already has an active token" in errors_on(changeset).current_user_id
    end

    test "allows same user_id for non-active tokens" do
      user_id = Ecto.UUID.generate()

      # Create first token
      insert(:token_schema, status: :available, current_user_id: user_id)

      # Create second token with same user_id
      changeset =
        TokenSchema.changeset(%TokenSchema{}, %{
          status: :available,
          current_user_id: user_id
        })

      assert {:ok, _token} = Repo.insert(changeset)
    end
  end

  describe "to_domain/1" do
    test "converts schema to domain entity" do
      now = DateTime.utc_now()
      token_usage = build(:token_usage_schema)

      schema = %TokenSchema{
        id: "test-id",
        status: :active,
        current_user_id: "user-id",
        activated_at: now,
        token_usages: [token_usage]
      }

      domain = TokenSchema.to_domain(schema)

      assert %Token{} = domain
      assert domain.id == "test-id"
      assert domain.status == :active
      assert domain.current_user_id == "user-id"
      assert domain.activated_at == now
      assert length(domain.token_usages) == 1
    end

    test "handles empty token usages" do
      schema = %TokenSchema{
        id: "test-id",
        token_usages: []
      }

      domain = TokenSchema.to_domain(schema)
      assert domain.token_usages == []
    end

    test "handles not loaded token usages" do
      schema = %TokenSchema{
        id: "test-id",
        token_usages: %Ecto.Association.NotLoaded{}
      }

      domain = TokenSchema.to_domain(schema)
      assert domain.token_usages == []
    end
  end

  describe "from_domain/1" do
    test "converts domain entity to schema" do
      now = DateTime.utc_now()

      domain = %Token{
        id: "test-id",
        status: :active,
        current_user_id: "user-id",
        activated_at: now
      }

      schema = TokenSchema.from_domain(domain)

      assert %TokenSchema{} = schema
      assert schema.id == "test-id"
      assert schema.status == :active
      assert schema.current_user_id == "user-id"
      assert schema.activated_at == now
    end
  end
end
