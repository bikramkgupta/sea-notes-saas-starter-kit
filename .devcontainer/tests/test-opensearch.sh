#!/bin/bash
# Test script for OpenSearch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="opensearch"
OPENSEARCH_HOST="${OPENSEARCH_HOST:-opensearch}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
OPENSEARCH_URL="http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"
TEST_INDEX="test_index_$(date +%s)"

print_header "OpenSearch"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."
    curl -sf -X DELETE "${OPENSEARCH_URL}/${TEST_INDEX}" 2>/dev/null || true
}

# Test 1: Connectivity (cluster health)
test_connectivity() {
    curl -sf "${OPENSEARCH_URL}/_cluster/health" > /dev/null 2>&1
}

# Test 2: Get cluster info
test_cluster_info() {
    result=$(curl -sf "${OPENSEARCH_URL}" 2>/dev/null | grep -o '"cluster_name"')
    [ -n "$result" ]
}

# Test 3: Create index
test_create_index() {
    result=$(curl -sf -X PUT "${OPENSEARCH_URL}/${TEST_INDEX}" \
        -H "Content-Type: application/json" \
        -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}' 2>/dev/null)
    echo "$result" | grep -q '"acknowledged":true'
}

# Test 4: List indices (verify created)
test_list_indices() {
    curl -sf "${OPENSEARCH_URL}/_cat/indices" 2>/dev/null | grep -q "$TEST_INDEX"
}

# Test 5: Index document
test_index_document() {
    result=$(curl -sf -X POST "${OPENSEARCH_URL}/${TEST_INDEX}/_doc/1" \
        -H "Content-Type: application/json" \
        -d '{"title": "Test Document", "content": "This is a test document", "timestamp": "'$(date -Iseconds)'"}' 2>/dev/null)
    echo "$result" | grep -q '"result":"created"\|"result":"updated"'
}

# Test 6: Index more documents
test_index_multiple() {
    for i in 2 3 4; do
        curl -sf -X POST "${OPENSEARCH_URL}/${TEST_INDEX}/_doc/$i" \
            -H "Content-Type: application/json" \
            -d '{"title": "Document '$i'", "content": "Content for document '$i'"}' > /dev/null 2>&1
    done
    # Refresh to make documents searchable
    curl -sf -X POST "${OPENSEARCH_URL}/${TEST_INDEX}/_refresh" > /dev/null 2>&1
}

# Test 7: Search documents
test_search_documents() {
    result=$(curl -sf -X GET "${OPENSEARCH_URL}/${TEST_INDEX}/_search" \
        -H "Content-Type: application/json" \
        -d '{"query": {"match_all": {}}}' 2>/dev/null)
    count=$(echo "$result" | grep -o '"total":{"value":[0-9]*' | grep -o '[0-9]*$')
    [ "$count" -ge 4 ]
}

# Test 8: Get document by ID
test_get_document() {
    result=$(curl -sf -X GET "${OPENSEARCH_URL}/${TEST_INDEX}/_doc/1" 2>/dev/null)
    echo "$result" | grep -q '"found":true'
}

# Test 9: Update document
test_update_document() {
    result=$(curl -sf -X POST "${OPENSEARCH_URL}/${TEST_INDEX}/_update/1" \
        -H "Content-Type: application/json" \
        -d '{"doc": {"title": "Updated Test Document"}}' 2>/dev/null)
    echo "$result" | grep -q '"result":"updated"\|"result":"noop"'
}

# Test 10: Delete document
test_delete_document() {
    result=$(curl -sf -X DELETE "${OPENSEARCH_URL}/${TEST_INDEX}/_doc/1" 2>/dev/null)
    echo "$result" | grep -q '"result":"deleted"'
}

# Test 11: Delete index
test_delete_index() {
    result=$(curl -sf -X DELETE "${OPENSEARCH_URL}/${TEST_INDEX}" 2>/dev/null)
    echo "$result" | grep -q '"acknowledged":true'
}

# Test 12: Verify index deleted
test_verify_index_deleted() {
    ! curl -sf "${OPENSEARCH_URL}/${TEST_INDEX}" > /dev/null 2>&1
}

# Main test execution
main() {
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        fail "curl not found. Please install curl."
        print_summary "OpenSearch"
        exit 1
    fi

    # Run tests
    run_test "Connectivity (cluster health)" test_connectivity
    run_test "Get cluster info" test_cluster_info
    run_test "Create index '${TEST_INDEX}'" test_create_index
    run_test "List indices (verify created)" test_list_indices
    run_test "Index document (ID: 1)" test_index_document
    run_test "Index multiple documents (IDs: 2-4)" test_index_multiple
    run_test "Search documents (verify 4+)" test_search_documents
    run_test "Get document by ID" test_get_document
    run_test "Update document" test_update_document
    run_test "Delete document" test_delete_document
    run_test "Delete index" test_delete_index
    run_test "Verify index deleted" test_verify_index_deleted

    print_summary "OpenSearch"
}

main "$@"
