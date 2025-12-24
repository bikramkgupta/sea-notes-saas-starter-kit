#!/bin/bash
# Test script for MongoDB

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="mongo"
MONGO_HOST="${MONGO_HOST:-mongo}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_USER="${MONGO_USER:-mongodb}"
MONGO_PASSWORD="${MONGO_PASSWORD:-mongodb}"
MONGO_DATABASE="${MONGO_DATABASE:-app}"
TEST_COLLECTION="test_collection_$(date +%s)"

print_header "MongoDB"

# Build connection string
MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/${MONGO_DATABASE}?authSource=admin"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."
    mongosh "$MONGO_URI" --quiet --eval "db.${TEST_COLLECTION}.drop();" 2>/dev/null || true
}

# Test 1: Connectivity
test_connectivity() {
    mongosh "$MONGO_URI" --quiet --eval "db.adminCommand('ping');" > /dev/null 2>&1
}

# Test 2: Create collection (implicit via insert)
test_create_collection() {
    mongosh "$MONGO_URI" --quiet --eval "db.createCollection('${TEST_COLLECTION}');" > /dev/null 2>&1
}

# Test 3: Insert documents
test_insert_documents() {
    mongosh "$MONGO_URI" --quiet --eval "
        db.${TEST_COLLECTION}.insertMany([
            { name: 'test_entry_1', value: 100 },
            { name: 'test_entry_2', value: 200 },
            { name: 'test_entry_3', value: 300 }
        ]);
    " > /dev/null 2>&1
}

# Test 4: Query documents
test_query_documents() {
    result=$(mongosh "$MONGO_URI" --quiet --eval "db.${TEST_COLLECTION}.countDocuments();" 2>/dev/null)
    [ "$result" = "3" ]
}

# Test 5: Update document
test_update_document() {
    mongosh "$MONGO_URI" --quiet --eval "
        db.${TEST_COLLECTION}.updateOne(
            { name: 'test_entry_1' },
            { \$set: { name: 'updated_entry', value: 999 } }
        );
    " > /dev/null 2>&1
}

# Test 6: Verify update
test_verify_update() {
    result=$(mongosh "$MONGO_URI" --quiet --eval "
        db.${TEST_COLLECTION}.findOne({ name: 'updated_entry' }).value;
    " 2>/dev/null)
    [ "$result" = "999" ]
}

# Test 7: Delete document
test_delete_document() {
    mongosh "$MONGO_URI" --quiet --eval "
        db.${TEST_COLLECTION}.deleteOne({ name: 'updated_entry' });
    " > /dev/null 2>&1
}

# Test 8: Verify delete
test_verify_delete() {
    result=$(mongosh "$MONGO_URI" --quiet --eval "db.${TEST_COLLECTION}.countDocuments();" 2>/dev/null)
    [ "$result" = "2" ]
}

# Test 9: Drop collection
test_drop_collection() {
    mongosh "$MONGO_URI" --quiet --eval "db.${TEST_COLLECTION}.drop();" > /dev/null 2>&1
}

# Test 10: Verify collection dropped
test_verify_collection_dropped() {
    result=$(mongosh "$MONGO_URI" --quiet --eval "
        db.getCollectionNames().includes('${TEST_COLLECTION}');
    " 2>/dev/null)
    [ "$result" = "false" ]
}

# Install mongosh from MongoDB repository
install_mongosh() {
    if command -v mongosh &> /dev/null; then
        return 0
    fi
    
    info "Installing MongoDB Shell (mongosh)..."
    
    # Install dependencies
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get install -y -qq gnupg curl 2>/dev/null
    
    # Import MongoDB public GPG key
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
        sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg 2>/dev/null
    
    # Add MongoDB repository (Ubuntu Noble 24.04)
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
        sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
    
    # Install mongosh
    sudo apt-get update -qq 2>/dev/null
    if sudo apt-get install -y -qq mongodb-mongosh 2>/dev/null; then
        success "Installed mongosh"
        return 0
    else
        fail "Failed to install mongosh"
        return 1
    fi
}

# Main test execution
main() {
    # Install mongosh if not available
    install_mongosh || {
        print_summary "MongoDB"
        exit 1
    }

    # Run tests
    run_test "Connectivity to MongoDB" test_connectivity
    run_test "Create collection '${TEST_COLLECTION}'" test_create_collection
    run_test "Insert 3 documents" test_insert_documents
    run_test "Query documents (verify 3 docs)" test_query_documents
    run_test "Update document" test_update_document
    run_test "Verify update" test_verify_update
    run_test "Delete document" test_delete_document
    run_test "Verify delete (2 docs remain)" test_verify_delete
    run_test "Drop collection" test_drop_collection
    run_test "Verify collection dropped" test_verify_collection_dropped

    print_summary "MongoDB"
}

main "$@"
