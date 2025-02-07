#!/bin/bash

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -l, --local     Run in local mode (default)"
    echo "  -d, --docker    Run in Docker mode"
    echo "  -h, --help      Show this help message"
    echo "  -s, --shell     Open a shell (only for Docker mode)"
    echo "  --psql          Open PostgreSQL shell"
    echo "  --reset-db      Reset the database"
    echo ""
    echo "Examples:"
    echo "  $0              # Run locally"
    echo "  $0 -d          # Run in Docker"
    echo "  $0 -d -s       # Open shell in Docker container"
}

# Default values
MODE="local"
COMMAND="run"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--local)
            MODE="local"
            shift
            ;;
        -d|--docker)
            MODE="docker"
            shift
            ;;
        -s|--shell)
            COMMAND="shell"
            shift
            ;;
        --psql)
            COMMAND="psql"
            shift
            ;;
        --reset-db)
            COMMAND="reset-db"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to run local development
run_local() {
    # Ensure local PostgreSQL is running (implement as needed)
    mix deps.get
    mix ecto.setup
    mix phx.server
}

# Function to run Docker development
run_docker() {
    docker-compose -f docker-compose.dev.yml up --build
}

# Function to open shell in Docker container
docker_shell() {
    docker-compose -f docker-compose.dev.yml exec app sh
}

# Function to open PostgreSQL shell
psql_shell() {
    if [ "$MODE" = "docker" ]; then
        docker-compose -f docker-compose.dev.yml exec db psql -U postgres token_manager_dev
    else
        psql -h localhost -p 5434 -U postgres token_manager_dev
    fi
}

# Function to reset database
reset_db() {
    if [ "$MODE" = "docker" ]; then
        docker-compose -f docker-compose.dev.yml exec app mix ecto.reset
    else
        mix ecto.reset
    fi
}

# Execute the appropriate command
case $COMMAND in
    "run")
        if [ "$MODE" = "docker" ]; then
            run_docker
        else
            run_local
        fi
        ;;
    "shell")
        if [ "$MODE" = "docker" ]; then
            docker_shell
        else
            echo "Shell command only available in Docker mode"
            exit 1
        fi
        ;;
    "psql")
        psql_shell
        ;;
    "reset-db")
        reset_db
        ;;
esac