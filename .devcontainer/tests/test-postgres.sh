#!/bin/bash
# Test script for PostgreSQL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="postgres"
PG_HOST="${PG_HOST:-postgres}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-postgres}"
PG_PASSWORD="${PG_PASSWORD:-password}"
PG_DATABASE="${PG_DATABASE:-app}"
TEST_TABLE="test_table_$(date +%s)"

print_header "PostgreSQL"

# Export password for psql
export PGPASSWORD="$PG_PASSWORD"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "DROP TABLE IF EXISTS ${TEST_TABLE};" 2>/dev/null || true
}

# Test 1: Connectivity
test_connectivity() {
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "SELECT 1;" > /dev/null 2>&1
}

# Test 2: Create table
test_create_table() {
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "CREATE TABLE ${TEST_TABLE} (id SERIAL PRIMARY KEY, name VARCHAR(100), created_at TIMESTAMP DEFAULT NOW());" > /dev/null 2>&1
}

# Test 3: Insert data
test_insert_data() {
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "INSERT INTO ${TEST_TABLE} (name) VALUES ('test_entry_1'), ('test_entry_2'), ('test_entry_3');" > /dev/null 2>&1
}

# Test 4: Query data
test_query_data() {
    result=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -t -c "SELECT COUNT(*) FROM ${TEST_TABLE};" 2>/dev/null | tr -d ' ')
    [ "$result" = "3" ]
}

# Test 5: Update data
test_update_data() {
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "UPDATE ${TEST_TABLE} SET name = 'updated_entry' WHERE name = 'test_entry_1';" > /dev/null 2>&1
}

# Test 6: Verify update
test_verify_update() {
    result=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -t -c "SELECT name FROM ${TEST_TABLE} WHERE name = 'updated_entry';" 2>/dev/null | tr -d ' ')
    [ "$result" = "updated_entry" ]
}

# Test 7: Delete data
test_delete_data() {
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "DELETE FROM ${TEST_TABLE} WHERE name = 'updated_entry';" > /dev/null 2>&1
}

# Test 8: Verify delete
test_verify_delete() {
    result=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -t -c "SELECT COUNT(*) FROM ${TEST_TABLE};" 2>/dev/null | tr -d ' ')
    [ "$result" = "2" ]
}

# Test 9: Drop table
test_drop_table() {
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "DROP TABLE ${TEST_TABLE};" > /dev/null 2>&1
}

# Test 10: Verify table dropped
test_verify_table_dropped() {
    ! psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        -c "SELECT 1 FROM ${TEST_TABLE} LIMIT 1;" > /dev/null 2>&1
}

# Main test execution
main() {
    # Install psql client if not available
    install_if_missing psql postgresql-client || {
        print_summary "PostgreSQL"
        exit 1
    }

    # Run tests
    run_test "Connectivity to PostgreSQL" test_connectivity
    run_test "Create table '${TEST_TABLE}'" test_create_table
    run_test "Insert 3 rows" test_insert_data
    run_test "Query data (verify 3 rows)" test_query_data
    run_test "Update data" test_update_data
    run_test "Verify update" test_verify_update
    run_test "Delete data" test_delete_data
    run_test "Verify delete (2 rows remain)" test_verify_delete
    run_test "Drop table" test_drop_table
    run_test "Verify table dropped" test_verify_table_dropped

    print_summary "PostgreSQL"
}

main "$@"
