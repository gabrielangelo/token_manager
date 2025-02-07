# Token Manager

## Introduction

Token Manager is a specialized system built with Elixir that manages a finite pool of tokens with strict lifecycle rules. The system maintains exactly 100 pre-generated tokens, handling their allocation, monitoring, and automatic release. This implementation focuses on reliability, concurrent access patterns, and maintaining consistency in a distributed environment.

## Technical Architecture

### State Management Strategy

The core of our token management system employs a hybrid approach to state management, combining ETS (Erlang Term Storage) with PostgreSQL. ETS serves as our primary read path, providing microsecond-level access to token states, while PostgreSQL acts as our source of truth and handles persistent storage.

We chose this dual-layer approach after careful consideration of the tradeoffs. ETS offers exceptional read performance and supports concurrent access patterns, crucial for our high-throughput requirements. However, ETS data exists only in memory and is node-local. PostgreSQL, while slower, provides durability and transaction support. This combination gives us the best of both worlds: fast reads for token status checks and reliable persistence for audit trails and recovery.

The system implements a GenServer-based TokenStateManager that synchronizes the ETS cache with the database. We use Phoenix PubSub for cross-node communication, ensuring state consistency across a distributed deployment. This design allows for horizontal scaling while maintaining strict token allocation rules.

### Token Lifecycle Management

Token lifecycle transitions are handled through a combination of synchronous operations and background jobs. When a token is activated, we use database transactions to ensure atomicity of the state change. The system schedules a cleanup job using Oban, setting up automatic release after the two-minute active period.

We chose Oban for background job processing because it provides several critical features:
- Unique job constraints prevent duplicate cleanup attempts
- Job persistence ensures cleanup occurs even after system restarts
- Built-in retry mechanisms handle transient failures gracefully
- Job scheduling precision is sufficient for our two-minute window

The cleanup strategy employs a two-pronged approach: scheduled individual cleanups and a periodic sweep for catching edge cases. This redundancy helps prevent token leaks while maintaining system efficiency.

### Concurrent Access Handling

Managing concurrent access to tokens presented several challenges, which we addressed through multiple mechanisms:

Database-level concurrency control uses SELECT FOR UPDATE SKIP LOCKED for token allocation, providing atomic, race-condition-free token reservation. This approach prevents double-allocation while maintaining high throughput, as competing transactions don't block each other.

The ETS layer uses :ets.select/2 with matching patterns for efficient token queries. We carefully chose table configuration options (:set, :protected, read_concurrency: true) to optimize for our access patterns while maintaining data consistency.

### Database Design

Our PostgreSQL schema emphasizes data integrity and query performance. We use UUID primary keys for tokens and usage records, enabling distributed ID generation without coordination. Foreign key constraints and indexes support our access patterns while maintaining referential integrity.

The schema includes a unique constraint preventing multiple active tokens per user, enforced at the database level. This provides an additional safety net beyond our application logic.

## Development Environment

### Prerequisites

The project requires:
- Elixir 1.15.7
- Erlang/OTP 26.2.1
- PostgreSQL 15
- Docker and Docker Compose (optional)

You can install the required Elixir and Erlang versions using ASDF version manager. The project includes a .tool-versions file that specifies the correct versions.

### Local Setup

The project supports both traditional local development and containerized workflows. 

#### Setting up with ASDF

First, install ASDF if you haven't already:

```bash
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1
```

Add the following to your shell configuration file (~/.bashrc, ~/.zshrc, etc.):

```bash
. "$HOME/.asdf/asdf.sh"
. "$HOME/.asdf/completions/asdf.bash"
```

Install the required plugins and versions:

```bash
# Install plugins
asdf plugin add erlang
asdf plugin add elixir

# Install versions specified in .tool-versions
asdf install

# Verify installations
elixir --version
erl -version
```

Install and start PostgreSQL:

```bash
# On Ubuntu/Debian
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib

# On macOS with Homebrew
brew install postgresql@15
brew services start postgresql@15
```

Then proceed with the project setup:

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start the application
mix phx.server
```

### Docker-based Development

We provide a comprehensive Docker-based development environment that closely mirrors production:

```bash
# Start development environment
./run-dev.sh -d

# Run tests in Docker
./run-tests.sh -d
```

The development environment includes hot code reloading, while the test environment is optimized for fast test execution.

## Testing Strategy

Our testing approach combines several layers of verification:

Unit tests cover individual modules and functions, with particular attention to token lifecycle state transitions and cleanup logic. Integration tests verify API endpoints and database interactions. Property-based tests explore edge cases in concurrent operations.

We use ExMachina for test data factories, ensuring consistent and relevant test data. Mox handles external service mocks when needed.

Run the test suite using:

```bash
# Full test suite
mix test

# With coverage reporting
mix test --cover

# Continuous testing during development
mix test.watch
```

## API Usage

The system provides a REST API for token management. Here are detailed examples of how to interact with each endpoint using curl commands.

### Token Activation

To activate a token for a user:

```bash
curl -X POST http://localhost:4000/api/tokens/activate \
  -H "Content-Type: application/json" \
  -d '{"user_id": "123e4567-e89b-12d3-a456-426614174000"}'
```

A successful response includes the token ID and usage details:

```json
{
  "data": {
    "token_id": "123e4567-e89b-12d3-a456-426614174000",
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "activated_at": "2025-02-07T14:30:00Z"
  }
}
```

### Listing All Tokens

To retrieve all tokens and their current states:

```bash
curl http://localhost:4000/api/tokens
```

The response includes all tokens with their status:

```json
{
  "data": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "status": "active",
      "current_user_id": "789e4567-e89b-12d3-a456-426614174000",
      "activated_at": "2025-02-07T14:30:00Z"
    },
    {
      "id": "456e4567-e89b-12d3-a456-426614174000",
      "status": "available",
      "current_user_id": null,
      "activated_at": null
    }
  ]
}
```

### Token Details

To get information about a specific token:

```bash
curl http://localhost:4000/api/tokens/123e4567-e89b-12d3-a456-426614174000
```

The response includes detailed token information:

```json
{
  "data": {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "status": "active",
    "current_user_id": "789e4567-e89b-12d3-a456-426614174000",
    "active_usage": {
      "user_id": "789e4567-e89b-12d3-a456-426614174000",
      "started_at": "2025-02-07T14:30:00Z"
    }
  }
}
```

### Token Usage History

To retrieve the usage history of a specific token:

```bash
curl http://localhost:4000/api/tokens/123e4567-e89b-12d3-a456-426614174000/history
```

The response shows all historical usages:

```json
{
  "data": {
    "token_id": "123e4567-e89b-12d3-a456-426614174000",
    "usages": [
      {
        "user_id": "789e4567-e89b-12d3-a456-426614174000",
        "started_at": "2025-02-07T14:30:00Z",
        "ended_at": "2025-02-07T14:32:00Z"
      }
    ]
  }
}
```

### Clearing Active Tokens

To release all currently active tokens:

```bash
curl -X POST http://localhost:4000/api/tokens/clear
```

The response confirms the number of tokens cleared:

```json
{
  "data": {
    "cleared_tokens": 3
  }
}
```

Each endpoint returns appropriate HTTP status codes: 200 for successful operations, 422 for validation errors, and 404 for not found resources. Error responses include descriptive messages to help identify and resolve issues.

## Dependencies

The system relies on several carefully chosen external dependencies:

- Phoenix: Web framework providing our REST API infrastructure
- Ecto: Database abstraction and query composition
- Oban: Background job processing with persistence
- ExMachina: Test data generation
- Credo: Static code analysis ensuring consistent style
- Dialyxir: Static type checking for early error detection

## Future Enhancements

Several areas have been identified for future improvement:

1. Metrics and Monitoring: Adding detailed Telemetry events for system behavior analysis
2. Rate Limiting: Implementing token bucket algorithm for API access control
3. Analytics Dashboard: Creating a web interface for token usage visualization
4. Enhanced Error Handling: Adding structured error responses and logging
5. API Documentation: Implementing OpenAPI/Swagger specifications

## Conclusion

Token Manager demonstrates a robust approach to managing finite resources in a distributed system. The architecture balances performance with reliability, while the code structure promotes maintainability and testability. Our choice of technologies and design patterns reflects careful consideration of the system's requirements and constraints.