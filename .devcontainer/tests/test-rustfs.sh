#!/bin/bash
# Test script for RustFS (S3-compatible object storage)
# Profile: minio (kept for backward compatibility)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="minio"
S3_ENDPOINT="http://minio:9000"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-rustfsadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-rustfsadmin}"
TEST_BUCKET="test-bucket-$(date +%s)"
TEST_FILE="test-file.txt"
TEST_CONTENT="Hello from RustFS test at $(date)"

print_header "RustFS (S3-compatible storage)"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."
    # Remove test file
    rm -f "/tmp/${TEST_FILE}" "/tmp/${TEST_FILE}.downloaded" 2>/dev/null || true
    # Remove test bucket and objects (ignore errors)
    aws --endpoint-url "$S3_ENDPOINT" s3 rb "s3://${TEST_BUCKET}" --force 2>/dev/null || true
}

# Check if AWS CLI is available
check_aws_cli() {
    if command -v aws &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Configure AWS CLI for RustFS
configure_aws() {
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
    export AWS_DEFAULT_REGION="us-east-1"
}

# Test 1: Connectivity
test_connectivity() {
    curl -sf "${S3_ENDPOINT}/health" > /dev/null 2>&1
}

# Test 2: Create bucket
test_create_bucket() {
    aws --endpoint-url "$S3_ENDPOINT" s3 mb "s3://${TEST_BUCKET}" > /dev/null 2>&1
}

# Test 3: List buckets
test_list_buckets() {
    aws --endpoint-url "$S3_ENDPOINT" s3 ls | grep -q "${TEST_BUCKET}"
}

# Test 4: Upload object
test_upload_object() {
    echo "$TEST_CONTENT" > "/tmp/${TEST_FILE}"
    aws --endpoint-url "$S3_ENDPOINT" s3 cp "/tmp/${TEST_FILE}" "s3://${TEST_BUCKET}/${TEST_FILE}" > /dev/null 2>&1
}

# Test 5: List objects
test_list_objects() {
    aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://${TEST_BUCKET}/" | grep -q "${TEST_FILE}"
}

# Test 6: Download object
test_download_object() {
    aws --endpoint-url "$S3_ENDPOINT" s3 cp "s3://${TEST_BUCKET}/${TEST_FILE}" "/tmp/${TEST_FILE}.downloaded" > /dev/null 2>&1
    [ -f "/tmp/${TEST_FILE}.downloaded" ]
}

# Test 7: Verify content
test_verify_content() {
    downloaded_content=$(cat "/tmp/${TEST_FILE}.downloaded")
    [ "$downloaded_content" = "$TEST_CONTENT" ]
}

# Test 8: Delete object
test_delete_object() {
    aws --endpoint-url "$S3_ENDPOINT" s3 rm "s3://${TEST_BUCKET}/${TEST_FILE}" > /dev/null 2>&1
}

# Test 9: Delete bucket
test_delete_bucket() {
    aws --endpoint-url "$S3_ENDPOINT" s3 rb "s3://${TEST_BUCKET}" > /dev/null 2>&1
}

# Test 10: Verify bucket deleted
test_verify_bucket_deleted() {
    ! aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://${TEST_BUCKET}" > /dev/null 2>&1
}

# Main test execution
main() {
    # Install AWS CLI if not available
    if ! check_aws_cli; then
        pip_install_if_missing aws awscli || {
            print_summary "RustFS"
            exit 1
        }
    fi

    # Configure AWS credentials
    configure_aws

    # Run tests
    run_test "Connectivity to RustFS" test_connectivity
    run_test "Create bucket '${TEST_BUCKET}'" test_create_bucket
    run_test "List buckets (verify created)" test_list_buckets
    run_test "Upload object '${TEST_FILE}'" test_upload_object
    run_test "List objects in bucket" test_list_objects
    run_test "Download object" test_download_object
    run_test "Verify downloaded content matches" test_verify_content
    run_test "Delete object" test_delete_object
    run_test "Delete bucket" test_delete_bucket
    run_test "Verify bucket deleted" test_verify_bucket_deleted

    print_summary "RustFS"
}

main "$@"
