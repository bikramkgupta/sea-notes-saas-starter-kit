# DevContainer Service Test Report

**Date:** December 20, 2025  
**Environment:** Ubuntu 24.04 (Noble) DevContainer

## Executive Summary

All 7 container services are operational and passing connectivity and functionality tests. The test suite validates network connectivity from the app container to each service, as well as basic CRUD operations.

| Service | Status | Tests Passed |
|---------|--------|--------------|
| PostgreSQL | PASSED | 10/10 |
| MySQL | PASSED | 10/10 |
| MongoDB | PASSED | 10/10 |
| Valkey (Redis) | PASSED | 11/11 |
| Kafka | PASSED | 10/10 |
| OpenSearch | PASSED | 12/12 |
| RustFS (S3) | PASSED | 10/10 |

**Total: 73 tests passed, 0 failed**

---

## Testing Approach

### Philosophy
Tests run **from the app container** to the service containers. This validates the actual network connectivity and DNS resolution that applications would use in a real scenario.

### Client Installation Strategy
Client tools are installed **on-the-fly** at test runtime:
- Keeps the base devcontainer image lean
- Ensures tests are self-contained and portable
- Acceptable in a container environment (no cleanup needed)
- Documents exactly which clients are needed for each service

### Clients Installed During Testing

| Service | Client Package | Installation Method |
|---------|----------------|---------------------|
| PostgreSQL | `postgresql-client` | apt |
| MySQL | `default-mysql-client` | apt |
| MongoDB | `mongodb-mongosh` | apt (MongoDB repo) |
| Valkey | `redis-tools` | apt (redis-cli compatible) |
| Kafka | `kcat` | apt |
| OpenSearch | `curl` | pre-installed |
| RustFS | `awscli` | pip |

---

## Service Details

### PostgreSQL
- **Image:** `postgres:18`
- **Port:** 5432
- **Credentials:** postgres/password
- **Database:** app
- **Tests:** Connect, CREATE TABLE, INSERT, SELECT, UPDATE, DELETE, DROP TABLE

### MySQL
- **Image:** `mysql:8`
- **Port:** 3306
- **Credentials:** mysql/mysql (root password: password)
- **Database:** app
- **Tests:** Connect, CREATE TABLE, INSERT, SELECT, UPDATE, DELETE, DROP TABLE

### MongoDB
- **Image:** `mongo:8`
- **Port:** 27017
- **Credentials:** mongodb/mongodb
- **Database:** app
- **Tests:** Connect, createCollection, insertMany, countDocuments, updateOne, deleteOne, drop

### Valkey (Redis-compatible)
- **Image:** `valkey/valkey:8`
- **Port:** 6379
- **Tests:** PING, SET, GET, HSET, HGET, LPUSH, LLEN, DEL, EXISTS

### Kafka
- **Image:** `confluentinc/cp-kafka:7.7.0`
- **Port:** 9092
- **Mode:** KRaft (no Zookeeper)
- **Tests:** Broker metadata, produce messages, consume messages, key-value messages, partition info

### OpenSearch
- **Image:** `opensearchproject/opensearch:3.0.0`
- **Port:** 9200
- **Security:** Disabled for development
- **Tests:** Cluster health, create index, index documents, search, update, delete

### RustFS (S3-compatible)
- **Image:** `rustfs/rustfs:latest`
- **Port:** 9000 (API), 9001 (Console)
- **Credentials:** rustfsadmin/rustfsadmin
- **Tests:** Health check, create bucket, upload object, list objects, download, verify content, delete

---

## Issues Fixed During Setup

### 1. RustFS Health Check
**Problem:** The docker-compose.yml used MinIO's health endpoint (`/minio/health/live`) which RustFS doesn't support.

**Solution:** Changed healthcheck to use `/health` endpoint:
```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:9000/health"]
```

### 2. Bash Arithmetic with `set -e`
**Problem:** When using `((TESTS_PASSED++))` with initial value 0, the post-increment returns 0 (falsy), causing script exit with `set -e`.

**Solution:** Changed to `((++TESTS_PASSED)) || true` to handle the edge case.

### 3. PEP 668 - Externally Managed Python Environment
**Problem:** Ubuntu 24.04 blocks system-wide pip installs per PEP 668.

**Solution:** Added `--break-system-packages` flag for pip installs (acceptable in container environment).

### 4. Kafka CLI Tools
**Problem:** Original tests required `kafka-topics.sh` which needs Java and the full Kafka distribution.

**Solution:** Switched to `kcat` (kafkacat) - a lightweight C-based Kafka CLI available via apt.

---

## Running the Tests

### Run All Tests
```bash
cd /workspaces/app
.devcontainer/tests/run-all-tests.sh --all
```

### Run Specific Service Tests
```bash
.devcontainer/tests/run-all-tests.sh postgres mysql
```

### Run Individual Test
```bash
.devcontainer/tests/test-postgres.sh
```

### List Available Services
```bash
.devcontainer/tests/run-all-tests.sh --list
```

---

## Network Architecture

All services communicate over the `devcontainer-network` bridge network:

```
┌─────────────────────────────────────────────────────────────────┐
│                    devcontainer-network                          │
│                                                                  │
│  ┌─────────┐                                                     │
│  │   app   │──────┬──────┬──────┬──────┬──────┬──────┬─────────│
│  └─────────┘      │      │      │      │      │      │         │
│                   ▼      ▼      ▼      ▼      ▼      ▼         │
│              ┌────────┬────────┬────────┬────────┬────────┐    │
│              │postgres│ mysql  │ mongo  │ valkey │ kafka  │    │
│              │ :5432  │ :3306  │ :27017 │ :6379  │ :9092  │    │
│              └────────┴────────┴────────┴────────┴────────┘    │
│                                                                  │
│              ┌────────────────┬─────────────────────────┐       │
│              │   opensearch   │         minio           │       │
│              │     :9200      │    :9000 (API)          │       │
│              │                │    :9001 (Console)      │       │
│              └────────────────┴─────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Recommendations

1. **First Run:** The first test run will install client packages, which takes 1-2 minutes. Subsequent runs are faster as clients are already installed.

2. **Container Recreation:** If containers are recreated, clients need to be reinstalled. This is by design for a lean container image.

3. **Custom Credentials:** For production use, update default credentials in `docker-compose.yml`.

4. **Health Checks:** All services include health checks. Wait for all services to be healthy before running tests.

---

*Report generated by DevContainer Test Suite*

