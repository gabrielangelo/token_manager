#!/bin/bash

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [TEST_FILE]"
    echo "Options:"
    echo "  -l, --local     Run tests locally"
    echo "  -d, --docker    Run tests in Docker (default)"
    echo "  -h, --help      Show this help message"
    echo "  -w, --watch     Run tests in watch mode (local only)"
    echo "  -c, --coverage  Run tests with coverage"
    echo ""
    echo "Examples:"
    echo "  $0 --local                    # Run all tests locally"
    echo "  $0 --docker                   # Run all tests in Docker"
    echo "  $0 -l test/my_test.exs        # Run specific test file locally"
    echo "  $0 -d test/my_test.exs        # Run specific test file in Docker"
    echo "  $0 -l -w                      # Run tests locally in watch mode"
    echo "  $0 -l -c                      # Run tests locally with coverage"
}

# Default values
RUN_MODE="docker"
WATCH_MODE=false
COVERAGE=false
TEST_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--local)
            RUN_MODE="local"
            shift
            ;;
        -d|--docker)
            RUN_MODE="docker"
            shift
            ;;
        -w|--watch)
            WATCH_MODE=true
            shift
            ;;
        -c|--coverage)
            COVERAGE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            TEST_FILE="$1"
            shift
            ;;
    esac
done

# Function to run local tests
run_local_tests() {
    # Ensure the test database exists
    mix ecto.create
    mix ecto.migrate

    if [ "$WATCH_MODE" = true ]; then
        if [ -n "$TEST_FILE" ]; then
            mix test.watch $TEST_FILE
        else
            mix test.watch
        fi
    elif [ "$COVERAGE" = true ]; then
        if [ -n "$TEST_FILE" ]; then
            mix test --cover $TEST_FILE
        else
            mix test --cover
        fi
    else
        if [ -n "$TEST_FILE" ]; then
            mix test $TEST_FILE
        else
            mix test
        fi
    fi
}

# Function to run Docker tests
run_docker_tests() {
    echo "Cleaning up any existing test containers..."
    docker-compose -f docker-compose.test.yml down -v

    echo "Starting test environment..."
    if [ -n "$TEST_FILE" ]; then
        docker-compose -f docker-compose.test.yml run --rm test mix test $TEST_FILE
    elif [ "$COVERAGE" = true ]; then
        docker-compose -f docker-compose.test.yml run --rm test mix test --cover
    else
        docker-compose -f docker-compose.test.yml up \
            --build \
            --abort-on-container-exit \
            --exit-code-from test
    fi

    echo "Cleaning up..."
    docker-compose -f docker-compose.test.yml down -v
}

# Run tests based on mode
if [ "$RUN_MODE" = "local" ]; then
    run_local_tests
else
    run_docker_tests
fi