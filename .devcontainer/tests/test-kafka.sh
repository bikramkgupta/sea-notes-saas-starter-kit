#!/bin/bash
# Test script for Kafka
# Uses kcat (kafkacat) - a lightweight Kafka CLI tool

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
SERVICE_NAME="kafka"
KAFKA_HOST="${KAFKA_HOST:-kafka}"
KAFKA_PORT="${KAFKA_PORT:-9092}"
BOOTSTRAP_SERVER="${KAFKA_HOST}:${KAFKA_PORT}"
TEST_TOPIC="test_topic_$(date +%s)"
TEST_MESSAGE="Hello from Kafka test at $(date)"

print_header "Kafka"

# Cleanup function - topics auto-delete is not available with kcat
# The test topic will remain but with unique timestamp names, this is acceptable
cleanup() {
    info "Cleaning up test resources..."
    # kcat doesn't support topic deletion, but test topics have unique names
    # They will be cleaned up when Kafka container is recreated
}

# Test 1: Connectivity (broker metadata)
test_connectivity() {
    kcat -b "$BOOTSTRAP_SERVER" -L > /dev/null 2>&1
}

# Test 2: Get broker metadata
test_broker_metadata() {
    result=$(kcat -b "$BOOTSTRAP_SERVER" -L 2>/dev/null | grep -c "broker")
    [ "$result" -ge 1 ]
}

# Test 3: Produce single message (topic auto-creates)
test_produce_message() {
    echo "$TEST_MESSAGE" | kcat -b "$BOOTSTRAP_SERVER" -P -t "$TEST_TOPIC" 2>/dev/null
}

# Test 4: List topics (verify created)
test_list_topics() {
    kcat -b "$BOOTSTRAP_SERVER" -L 2>/dev/null | grep -q "$TEST_TOPIC"
}

# Test 5: Consume message
test_consume_message() {
    result=$(timeout 10 kcat -b "$BOOTSTRAP_SERVER" -C -t "$TEST_TOPIC" -o beginning -c 1 -e 2>/dev/null)
    [ "$result" = "$TEST_MESSAGE" ]
}

# Test 6: Produce multiple messages
test_produce_multiple() {
    printf "Message 1\nMessage 2\nMessage 3\n" | kcat -b "$BOOTSTRAP_SERVER" -P -t "$TEST_TOPIC" 2>/dev/null
}

# Test 7: Consume multiple messages
test_consume_multiple() {
    count=$(timeout 10 kcat -b "$BOOTSTRAP_SERVER" -C -t "$TEST_TOPIC" -o beginning -c 4 -e 2>/dev/null | wc -l)
    [ "$count" -ge 4 ]
}

# Test 8: Produce with key
test_produce_with_key() {
    echo "key1:value1" | kcat -b "$BOOTSTRAP_SERVER" -P -t "$TEST_TOPIC" -K: 2>/dev/null
    # Give Kafka a moment to process
    sleep 1
}

# Test 9: Consume with key (read last message)
test_consume_with_key() {
    # Consume all messages and check if any contains our key
    result=$(timeout 10 kcat -b "$BOOTSTRAP_SERVER" -C -t "$TEST_TOPIC" -o beginning -e -K: 2>/dev/null | grep "key1" | head -1)
    [ -n "$result" ]
}

# Test 10: Get topic partition info
test_partition_info() {
    result=$(kcat -b "$BOOTSTRAP_SERVER" -L -t "$TEST_TOPIC" 2>/dev/null | grep -c "partition")
    [ "$result" -ge 1 ]
}

# Main test execution
main() {
    # Install kcat if not available
    install_if_missing kcat kcat || {
        print_summary "Kafka"
        exit 1
    }

    # Run tests
    run_test "Connectivity to Kafka" test_connectivity
    run_test "Get broker metadata" test_broker_metadata
    run_test "Produce message (topic auto-creates)" test_produce_message
    run_test "List topics (verify created)" test_list_topics
    run_test "Consume message" test_consume_message
    run_test "Produce multiple messages" test_produce_multiple
    run_test "Consume multiple messages" test_consume_multiple
    run_test "Produce message with key" test_produce_with_key
    run_test "Consume message with key" test_consume_with_key
    run_test "Get topic partition info" test_partition_info

    print_summary "Kafka"
}

main "$@"
