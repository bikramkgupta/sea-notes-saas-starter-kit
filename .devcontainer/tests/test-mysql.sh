#!/bin/bash
# Test script for MySQL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="mysql"
MYSQL_HOST="${MYSQL_HOST:-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-mysql}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-mysql}"
MYSQL_DATABASE="${MYSQL_DATABASE:-app}"
TEST_TABLE="test_table_$(date +%s)"

print_header "MySQL"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "DROP TABLE IF EXISTS ${TEST_TABLE};" 2>/dev/null || true
}

# Test 1: Connectivity
test_connectivity() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "SELECT 1;" > /dev/null 2>&1
}

# Test 2: Create table
test_create_table() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "CREATE TABLE ${TEST_TABLE} (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
}

# Test 3: Insert data
test_insert_data() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "INSERT INTO ${TEST_TABLE} (name) VALUES ('test_entry_1'), ('test_entry_2'), ('test_entry_3');" 2>/dev/null
}

# Test 4: Query data
test_query_data() {
    result=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -N -e "SELECT COUNT(*) FROM ${TEST_TABLE};" 2>/dev/null)
    [ "$result" = "3" ]
}

# Test 5: Update data
test_update_data() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "UPDATE ${TEST_TABLE} SET name = 'updated_entry' WHERE name = 'test_entry_1';" 2>/dev/null
}

# Test 6: Verify update
test_verify_update() {
    result=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -N -e "SELECT name FROM ${TEST_TABLE} WHERE name = 'updated_entry';" 2>/dev/null)
    [ "$result" = "updated_entry" ]
}

# Test 7: Delete data
test_delete_data() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "DELETE FROM ${TEST_TABLE} WHERE name = 'updated_entry';" 2>/dev/null
}

# Test 8: Verify delete
test_verify_delete() {
    result=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -N -e "SELECT COUNT(*) FROM ${TEST_TABLE};" 2>/dev/null)
    [ "$result" = "2" ]
}

# Test 9: Drop table
test_drop_table() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "DROP TABLE ${TEST_TABLE};" 2>/dev/null
}

# Test 10: Verify table dropped
test_verify_table_dropped() {
    ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
        -e "SELECT 1 FROM ${TEST_TABLE} LIMIT 1;" 2>/dev/null
}

# Main test execution
main() {
    # Install mysql client if not available
    install_if_missing mysql default-mysql-client || {
        print_summary "MySQL"
        exit 1
    }

    # Run tests
    run_test "Connectivity to MySQL" test_connectivity
    run_test "Create table '${TEST_TABLE}'" test_create_table
    run_test "Insert 3 rows" test_insert_data
    run_test "Query data (verify 3 rows)" test_query_data
    run_test "Update data" test_update_data
    run_test "Verify update" test_verify_update
    run_test "Delete data" test_delete_data
    run_test "Verify delete (2 rows remain)" test_verify_delete
    run_test "Drop table" test_drop_table
    run_test "Verify table dropped" test_verify_table_dropped

    print_summary "MySQL"
}

main "$@"
