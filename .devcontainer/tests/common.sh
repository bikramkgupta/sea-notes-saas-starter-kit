#!/bin/bash
# Common helper functions for service tests
# Source this file in individual test scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Track if apt has been updated this session
APT_UPDATED=false

# Install a package if the command is not available
# Usage: install_if_missing <command> [package_name]
# If package_name is not provided, command name is used
install_if_missing() {
    local cmd="$1"
    local package="${2:-$1}"
    
    if command -v "$cmd" &> /dev/null; then
        return 0
    fi
    
    info "Installing $package (provides $cmd)..."
    
    if [ "$APT_UPDATED" = false ]; then
        sudo apt-get update -qq 2>/dev/null
        APT_UPDATED=true
    fi
    
    if sudo apt-get install -y -qq "$package" 2>/dev/null; then
        success "Installed $package"
        return 0
    else
        fail "Failed to install $package"
        return 1
    fi
}

# Install Python package via pip
# Usage: pip_install_if_missing <command> <pip_package>
# Note: Uses --break-system-packages for Ubuntu 24.04+ (PEP 668)
# This is acceptable in a container environment
pip_install_if_missing() {
    local cmd="$1"
    local package="$2"
    
    if command -v "$cmd" &> /dev/null; then
        return 0
    fi
    
    info "Installing $package via pip..."
    
    # Try with --break-system-packages for Ubuntu 24.04+ (PEP 668)
    if pip install --quiet --break-system-packages "$package" 2>/dev/null || \
       pip3 install --quiet --break-system-packages "$package" 2>/dev/null || \
       pip install --quiet "$package" 2>/dev/null || \
       pip3 install --quiet "$package" 2>/dev/null; then
        success "Installed $package"
        return 0
    else
        fail "Failed to install $package via pip"
        return 1
    fi
}

# Print colored status messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((++TESTS_PASSED)) || true
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((++TESTS_FAILED)) || true
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Print test header
print_header() {
    local service="$1"
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Testing: ${service}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Print test summary
print_summary() {
    local service="$1"
    echo ""
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "  ${service} Test Summary"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "  ${GREEN}Passed:${NC} ${TESTS_PASSED}"
    echo -e "  ${RED}Failed:${NC} ${TESTS_FAILED}"
    echo -e "${BLUE}----------------------------------------${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "  ${RED}OVERALL: FAILED${NC}"
        return 1
    else
        echo -e "  ${GREEN}OVERALL: PASSED${NC}"
        return 0
    fi
}

# Check if a service is running
check_service_running() {
    local service="$1"
    local compose_file="${2:-.devcontainer/docker-compose.yml}"

    if docker compose -f "$compose_file" ps --status running "$service" 2>/dev/null | grep -q "$service"; then
        return 0
    else
        return 1
    fi
}

# Wait for a service to be healthy
wait_for_healthy() {
    local service="$1"
    local max_attempts="${2:-30}"
    local compose_file="${3:-.devcontainer/docker-compose.yml}"

    info "Waiting for $service to be healthy..."

    for i in $(seq 1 $max_attempts); do
        if docker compose -f "$compose_file" ps "$service" 2>/dev/null | grep -q "healthy"; then
            success "$service is healthy"
            return 0
        fi
        sleep 2
    done

    fail "$service did not become healthy within $((max_attempts * 2)) seconds"
    return 1
}

# Execute command in a container
exec_in_container() {
    local service="$1"
    shift
    local compose_file="${COMPOSE_FILE:-.devcontainer/docker-compose.yml}"

    docker compose -f "$compose_file" exec -T "$service" "$@"
}

# Run a test with description
run_test() {
    local description="$1"
    shift

    info "Testing: $description"
    if "$@"; then
        success "$description"
        return 0
    else
        fail "$description"
        return 1
    fi
}

# Cleanup function - can be overridden in test scripts
cleanup() {
    info "Cleaning up test resources..."
}

# Trap to ensure cleanup runs on exit
trap cleanup EXIT
