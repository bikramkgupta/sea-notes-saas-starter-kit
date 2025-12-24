#!/bin/bash
# Master test runner for all devcontainer services
# Run this script to test all available services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Track results
declare -A TEST_RESULTS
TOTAL_PASSED=0
TOTAL_FAILED=0

# Available services and their test scripts
declare -A SERVICES=(
    ["postgres"]="test-postgres.sh"
    ["minio"]="test-rustfs.sh"
    ["mysql"]="test-mysql.sh"
    ["mongo"]="test-mongo.sh"
    ["valkey"]="test-valkey.sh"
    ["kafka"]="test-kafka.sh"
    ["opensearch"]="test-opensearch.sh"
)

# Service display names
declare -A SERVICE_NAMES=(
    ["postgres"]="PostgreSQL"
    ["minio"]="RustFS (S3)"
    ["mysql"]="MySQL"
    ["mongo"]="MongoDB"
    ["valkey"]="Valkey"
    ["kafka"]="Kafka"
    ["opensearch"]="OpenSearch"
)

print_banner() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         DevContainer Service Test Suite                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_usage() {
    echo "Usage: $0 [OPTIONS] [service...]"
    echo ""
    echo "Run tests for devcontainer services."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -l, --list     List available services"
    echo "  -a, --all      Run tests for all running services"
    echo ""
    echo "Services:"
    for svc in "${!SERVICE_NAMES[@]}"; do
        echo "  $svc    ${SERVICE_NAMES[$svc]}"
    done
    echo ""
    echo "Examples:"
    echo "  $0 postgres          # Test PostgreSQL only"
    echo "  $0 postgres minio    # Test PostgreSQL and RustFS"
    echo "  $0 --all             # Test all running services"
    echo ""
}

list_services() {
    echo ""
    echo "Available services:"
    echo ""
    for svc in "${!SERVICE_NAMES[@]}"; do
        printf "  %-12s %s\n" "$svc" "${SERVICE_NAMES[$svc]}"
    done
    echo ""
}

# Check if a service container is running
is_service_running() {
    local service="$1"
    docker compose -f .devcontainer/docker-compose.yml ps --status running "$service" 2>/dev/null | grep -q "$service"
}

# Get list of running services
get_running_services() {
    local running=()
    for svc in "${!SERVICES[@]}"; do
        if is_service_running "$svc"; then
            running+=("$svc")
        fi
    done
    echo "${running[@]}"
}

# Run test for a specific service
run_service_test() {
    local service="$1"
    local test_script="${SERVICES[$service]}"
    local display_name="${SERVICE_NAMES[$service]}"

    if [ -z "$test_script" ]; then
        echo -e "${RED}[ERROR]${NC} Unknown service: $service"
        return 1
    fi

    local script_path="${SCRIPT_DIR}/${test_script}"

    if [ ! -f "$script_path" ]; then
        echo -e "${RED}[ERROR]${NC} Test script not found: $script_path"
        return 1
    fi

    # Check if service is running
    if ! is_service_running "$service"; then
        echo -e "${YELLOW}[SKIP]${NC} ${display_name} - service not running"
        TEST_RESULTS[$service]="skipped"
        return 0
    fi

    # Run the test
    echo -e "${BLUE}[TEST]${NC} Running tests for ${display_name}..."

    if bash "$script_path"; then
        TEST_RESULTS[$service]="passed"
        ((++TOTAL_PASSED)) || true
    else
        TEST_RESULTS[$service]="failed"
        ((++TOTAL_FAILED)) || true
    fi
}

# Print final summary
print_final_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Final Test Summary                      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    for service in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$service]}"
        local display_name="${SERVICE_NAMES[$service]}"

        case "$result" in
            passed)
                echo -e "  ${GREEN}✓${NC} ${display_name}: ${GREEN}PASSED${NC}"
                ;;
            failed)
                echo -e "  ${RED}✗${NC} ${display_name}: ${RED}FAILED${NC}"
                ;;
            skipped)
                echo -e "  ${YELLOW}○${NC} ${display_name}: ${YELLOW}SKIPPED${NC} (not running)"
                ;;
        esac
    done

    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "  Services Passed:  ${GREEN}${TOTAL_PASSED}${NC}"
    echo -e "  Services Failed:  ${RED}${TOTAL_FAILED}${NC}"
    echo -e "  Services Skipped: ${YELLOW}$((${#TEST_RESULTS[@]} - TOTAL_PASSED - TOTAL_FAILED))${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"

    if [ "$TOTAL_FAILED" -gt 0 ]; then
        echo -e "  ${RED}OVERALL: FAILED${NC}"
        echo ""
        return 1
    else
        echo -e "  ${GREEN}OVERALL: PASSED${NC}"
        echo ""
        return 0
    fi
}

# Main
main() {
    local services_to_test=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -l|--list)
                list_services
                exit 0
                ;;
            -a|--all)
                read -ra services_to_test <<< "$(get_running_services)"
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                services_to_test+=("$1")
                shift
                ;;
        esac
    done

    # If no services specified, show usage
    if [ ${#services_to_test[@]} -eq 0 ]; then
        print_banner
        echo "No services specified. Use --all to test all running services."
        echo ""
        print_usage
        exit 0
    fi

    print_banner

    echo "Services to test: ${services_to_test[*]}"
    echo ""

    # Run tests for each service
    for service in "${services_to_test[@]}"; do
        run_service_test "$service"
    done

    # Print final summary
    print_final_summary
}

main "$@"
