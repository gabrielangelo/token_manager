defmodule TokenManager.TokenFactory do
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenSchema
  alias TokenManager.Infrastructure.Persistence.Schemas.TokenUsageSchema

  defmacro __using__(_opts) do
    quote do
      def token_schema_factory do
        %TokenSchema{
          id: Ecto.UUID.generate(),
          status: :available,
          current_user_id: nil,
          activated_at: nil
        }
      end

      def active_token_schema_factory do
        struct!(
          token_schema_factory(),
          %{
            status: :active,
            current_user_id: Ecto.UUID.generate(),
            activated_at: DateTime.utc_now()
          }
        )
      end

      def token_usage_schema_factory do
        %TokenUsageSchema{
          id: Ecto.UUID.generate(),
          token_id: nil,
          user_id: Ecto.UUID.generate(),
          started_at: DateTime.utc_now(),
          ended_at: nil
        }
      end
    end
  end
end
