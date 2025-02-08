# Token Manager

## Introduction

Token Manager is an Elixir-based system that handles a pool of 100 tokens. The system allocates tokens to users, monitors their usage, and automatically retrieves them after a set period. Built for reliability, the system handles multiple users requesting tokens simultaneously while maintaining consistent behavior across distributed environments.

## Technical Architecture

### State Management Strategy

Token Manager uses a dual approach to state management by combining ETS (Erlang Term Storage) and PostgreSQL. ETS provides quick access to token states, while PostgreSQL serves as the permanent data store.

The system adopts this dual-layer approach based on practical needs. ETS delivers fast read performance and handles multiple users accessing tokens at once, meeting the demands of high-traffic periods. While ETS keeps data in memory and operates on single nodes, PostgreSQL provides permanent storage and supports complex transactions. Together, they create a balanced solution: ETS handles rapid token status checks while PostgreSQL maintains reliable records for auditing and recovery.

A TokenStateManager keeps ETS and the database synchronized. The system uses Phoenix PubSub for communication between different parts, allowing for future expansion while maintaining token tracking.

### Token Lifecycle Management

The system manages token transitions through immediate actions and scheduled tasks. When activating a token, database transactions ensure proper ordering of all changes. The system then uses Oban to schedule automatic token release after two minutes of use.

Oban handles background tasks because it:
- Prevents duplicate cleanup attempts
- Maintains scheduled tasks even through system restarts
- Continues trying if initial attempts fail
- Handles the two-minute timing requirements

To keep tokens moving smoothly, the system employs two cleanup methods: individual scheduled releases and regular checks for any overlooked tokens.

### Concurrent Access Handling

Managing tokens during periods of high demand requires careful coordination. The system addresses this through several mechanisms:

For database operations, SELECT FOR UPDATE SKIP LOCKED ensures reliable token allocation. This approach lets one user receive a token while others can immediately try for different ones, avoiding delays.

The ETS layer uses specific configuration settings (:set, :protected, read_concurrency: true) to optimize token status checks when many users need access simultaneously.

### Database Design

The PostgreSQL database emphasizes organization and efficient retrieval. It uses UUID identifiers for tokens and usage records, allowing for independent record creation across multiple servers. The database includes rules to maintain proper connections between related data.

The system deliberately omits a dedicated user management system to maintain focus on the token state machine implementation. Instead, it uses UUID strings to simulate user identifiers, which adequately serves the core token management functionality without introducing the complexity of user authentication and management.

## Development Environment

### Prerequisites

Running the project requires:
- Elixir 1.15.7
- Erlang/OTP 26.2.1
- PostgreSQL 15
- Docker and Docker Compose (optional)

The ASDF version manager can install the required Elixir and Erlang versions using the included .tool-versions file.

### Local Setup

Developers can choose between traditional local development or containerized workflows.

#### Setting up with ASDF

Begin by installing ASDF:

```bash
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1
```

Add these lines to your shell configuration file (~/.bashrc, ~/.zshrc, etc.):

```bash
. "$HOME/.asdf/asdf.sh"
. "$HOME/.asdf/completions/asdf.bash"
```

Install required software:

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

Set up PostgreSQL:

```bash
# On Ubuntu/Debian
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib

# On macOS with Homebrew
brew install postgresql@15
brew services start postgresql@15
```

Complete the project setup:

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start the application
mix phx.server
```

### Docker-based Development

For containerized development:

```bash
# Start development environment
./run-dev.sh -d

# Run tests in Docker
./run-tests.sh -d
```

The development container includes automatic code reloading, while the test container focuses on quick test execution.

## Testing Strategy

The testing approach covers multiple aspects of the system:

Unit tests examine individual components, focusing on token lifecycle changes and cleanup procedures. Integration tests verify API functionality and database operations. Property-based tests check behavior under various concurrent scenarios.

ExMachina creates consistent test data, while Mox handles external service simulation. Run tests using:

```bash
# Full test suite
mix test

# With coverage reporting
mix test --cover

# Continuous testing during development
mix test.watch
```

# API Usage

The Token Manager provides a REST API for token operations. All endpoints handle JSON data and return consistent response formats. Here's how to use each endpoint:

## Endpoints Overview

### Activate a Token

Request a new token for a user:

```bash
curl -X POST http://localhost:4000/api/tokens/activate \
  -H "Content-Type: application/json" \
  -d '{"user_id": "123e4567-e89b-12d3-a456-426614174000"}'
```

Success response (200 OK):
```json
{
  "data": {
    "token_id": "123e4567-e89b-12d3-a456-426614174000",
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "activated_at": "2025-02-07T14:30:00Z"
  }
}
```

Error response (422 Unprocessable Entity):
```json
{
  "errors": {
    "user_id": ["already has an active token"]
  }
}
```

### List All Tokens

Get the status of all tokens in the system:

```bash
curl http://localhost:4000/api/tokens
```

Response (200 OK):
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
  ],
  "meta": {
    "total_count": 100,
    "active_count": 1,
    "available_count": 99
  }
}
```

### Get Token Details

Retrieve information about a specific token:

```bash
curl http://localhost:4000/api/tokens/123e4567-e89b-12d3-a456-426614174000
```

Success response (200 OK):
```json
{
  "data": {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "status": "active",
    "current_user_id": "789e4567-e89b-12d3-a456-426614174000",
    "active_usage": {
      "user_id": "789e4567-e89b-12d3-a456-426614174000",
      "started_at": "2025-02-07T14:30:00Z",
      "expires_at": "2025-02-07T14:32:00Z"
    }
  }
}
```

Error response (404 Not Found):
```json
{
  "errors": {
    "token": ["not found"]
  }
}
```

### View Token History

Get the usage history of a specific token:

```bash
curl http://localhost:4000/api/tokens/123e4567-e89b-12d3-a456-426614174000/history
```

Response (200 OK):
```json
{
  "data": {
    "token_id": "123e4567-e89b-12d3-a456-426614174000",
    "usages": [
      {
        "user_id": "789e4567-e89b-12d3-a456-426614174000",
        "started_at": "2025-02-07T14:30:00Z",
        "ended_at": "2025-02-07T14:32:00Z"
      },
      {
        "user_id": "456e4567-e89b-12d3-a456-426614174000",
        "started_at": "2025-02-07T14:25:00Z",
        "ended_at": "2025-02-07T14:27:00Z"
      }
    ],
    "meta": {
      "total_usages": 2
    }
  }
}
```

### Clear Active Tokens

Release all currently active tokens:

```bash
curl -X POST http://localhost:4000/api/tokens/clear
```

Response (200 OK):
```json
{
  "data": {
    "cleared_tokens": 3,
    "message": "Successfully cleared all active tokens"
  }
}
```

## Response Codes

The API uses standard HTTP status codes:

- 200: Successful operation
- 400: Bad request (invalid input)
- 404: Resource not found
- 422: Validation error
- 500: Server error

## Request Rate Limits

- Maximum 100 requests per minute per IP address
- Burst allowance of 20 requests
- Rate limit headers included in responses:
  - X-RateLimit-Limit
  - X-RateLimit-Remaining
  - X-RateLimit-Reset

## Notes

- All timestamps are in UTC and follow ISO 8601 format
- Token IDs and user IDs must be valid UUIDs
- Active tokens automatically expire after 2 minutes
- A user can only have one active token at a time
- The system maintains exactly 100 tokens total

## Dependencies

Token Manager relies on selected external tools:

- Phoenix: Powers the REST API
- Ecto: Handles database operations
- Oban: Manages background tasks
- ExMachina: Supports testing
- Credo: Maintains code quality
- Dialyxir: Checks types during development

## Future Development

Planned improvements include:

1. System monitoring through Telemetry events
2. Request rate control using token bucket algorithm
3. Visual interface for token usage data
4. Enhanced error handling and logging
5. OpenAPI/Swagger documentation

## Conclusion

Token Manager demonstrates acceptable resource management in distributed systems. Its design balances quick response times with reliable operation, creating a maintainable and testable solution for token handling.
