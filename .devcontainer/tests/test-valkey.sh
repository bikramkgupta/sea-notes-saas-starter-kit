#!/bin/bash
# Test script for Valkey (Redis-compatible)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="valkey"
VALKEY_HOST="${VALKEY_HOST:-valkey}"
VALKEY_PORT="${VALKEY_PORT:-6379}"
TEST_KEY="test_key_$(date +%s)"
TEST_HASH="test_hash_$(date +%s)"
TEST_LIST="test_list_$(date +%s)"

print_header "Valkey (Redis-compatible)"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."
    valkey-cli -h "$VALKEY_HOST" -p "$VALKEY_PORT" DEL "$TEST_KEY" "$TEST_HASH" "$TEST_LIST" 2>/dev/null || true
}

# Helper to run valkey-cli commands
vcli() {
    valkey-cli -h "$VALKEY_HOST" -p "$VALKEY_PORT" "$@"
}

# Test 1: Connectivity (PING)
test_connectivity() {
    result=$(vcli PING 2>/dev/null)
    [ "$result" = "PONG" ]
}

# Test 2: SET key
test_set_key() {
    result=$(vcli SET "$TEST_KEY" "test_value" 2>/dev/null)
    [ "$result" = "OK" ]
}

# Test 3: GET key
test_get_key() {
    result=$(vcli GET "$TEST_KEY" 2>/dev/null)
    [ "$result" = "test_value" ]
}

# Test 4: UPDATE key (overwrite)
test_update_key() {
    result=$(vcli SET "$TEST_KEY" "updated_value" 2>/dev/null)
    [ "$result" = "OK" ]
}

# Test 5: Verify update
test_verify_update() {
    result=$(vcli GET "$TEST_KEY" 2>/dev/null)
    [ "$result" = "updated_value" ]
}

# Test 6: HSET (hash operations)
test_hash_set() {
    result=$(vcli HSET "$TEST_HASH" field1 "value1" field2 "value2" 2>/dev/null)
    [ "$result" = "2" ]
}

# Test 7: HGET (hash get)
test_hash_get() {
    result=$(vcli HGET "$TEST_HASH" field1 2>/dev/null)
    [ "$result" = "value1" ]
}

# Test 8: LPUSH (list operations)
test_list_push() {
    result=$(vcli LPUSH "$TEST_LIST" "item1" "item2" "item3" 2>/dev/null)
    [ "$result" = "3" ]
}

# Test 9: LRANGE (list get)
test_list_range() {
    result=$(vcli LLEN "$TEST_LIST" 2>/dev/null)
    [ "$result" = "3" ]
}

# Test 10: DEL keys
test_delete_keys() {
    result=$(vcli DEL "$TEST_KEY" "$TEST_HASH" "$TEST_LIST" 2>/dev/null)
    [ "$result" = "3" ]
}

# Test 11: Verify delete
test_verify_delete() {
    result=$(vcli EXISTS "$TEST_KEY" "$TEST_HASH" "$TEST_LIST" 2>/dev/null)
    [ "$result" = "0" ]
}

# Main test execution
main() {
    # Install redis-tools if neither valkey-cli nor redis-cli is available
    # redis-cli is compatible with Valkey
    if command -v valkey-cli &> /dev/null; then
        : # valkey-cli is available
    elif command -v redis-cli &> /dev/null; then
        warn "valkey-cli not found, using redis-cli (compatible)"
        vcli() {
            redis-cli -h "$VALKEY_HOST" -p "$VALKEY_PORT" "$@"
        }
    else
        install_if_missing redis-cli redis-tools || {
            print_summary "Valkey"
            exit 1
        }
        # Redefine vcli to use redis-cli
        vcli() {
            redis-cli -h "$VALKEY_HOST" -p "$VALKEY_PORT" "$@"
        }
    fi

    # Run tests
    run_test "Connectivity (PING/PONG)" test_connectivity
    run_test "SET key" test_set_key
    run_test "GET key" test_get_key
    run_test "UPDATE key (overwrite)" test_update_key
    run_test "Verify update" test_verify_update
    run_test "HSET (hash with 2 fields)" test_hash_set
    run_test "HGET (hash field)" test_hash_get
    run_test "LPUSH (list with 3 items)" test_list_push
    run_test "LLEN (list length)" test_list_range
    run_test "DEL (delete all test keys)" test_delete_keys
    run_test "Verify keys deleted" test_verify_delete

    print_summary "Valkey"
}

main "$@"
