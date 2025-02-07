# Build stage
FROM hexpm/elixir:1.15.7-erlang-26.2.1-alpine-3.19.1 AS builder

# Install build dependencies
RUN apk add --no-cache build-base git

# Set environment variables
ENV MIX_ENV=prod

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy config files first to cache dependencies
COPY mix.exs mix.lock ./
COPY config config

# Install dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application files
COPY lib lib
COPY priv priv

# Compile and create release
RUN mix compile
RUN mix release

# Release stage
FROM alpine:3.19.1

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Set runtime environment variables
ENV MIX_ENV=prod \
    PORT=4000

# Copy release from builder stage
COPY --from=builder /app/_build/prod/rel/token_manager ./

# Command to start the application
CMD ["/app/bin/token_manager", "start"]