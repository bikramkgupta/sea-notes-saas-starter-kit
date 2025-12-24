# Dev Container Setup

> **Experimental**: This is a personal project and is not officially supported by DigitalOcean. APIs may change without notice.

This is part of 3 projects to scale Agentic workflows with DigitalOcean App Platform. The concepts are generic and should work with any PaaS:
- Safe local sandboxing using DevContainers (this repo or [do-app-devcontainer](https://github.com/bikramkgupta/do-app-devcontainer))
- Rapid development iteration using hot reload ([do-app-hot-reload-template](https://github.com/bikramkgupta/do-app-hot-reload-template))
- Disposable environments using sandboxes for parallel experimentation and debugging ([do-app-sandbox](https://github.com/bikramkgupta/do-app-sandbox))

---

## AI Assistant Guidance

> **Important**: If you are an AI assistant helping set up this devcontainer, follow the three phases below exactly. Do not modify workspace paths (`/workspaces/app`), Docker Compose service names, or reinvent the configuration. The setup is designed to work out of the box.

**The Three Phases:**
1. **Phase 1**: Copy the `.devcontainer` folder to the target project
2. **Phase 2**: Configure features based on the project's framework
3. **Phase 3**: Handle S3-compatible storage (RustFS vs DigitalOcean Spaces)

Most services (PostgreSQL, MySQL, MongoDB, Kafka, Valkey, OpenSearch) work identically between local and cloud. **Only storage (RustFS/MinIO vs DigitalOcean Spaces) requires code changes** - Phase 3 provides the patterns.

---

## Phase 1: Copy DevContainer to Project

Copy the entire `.devcontainer` folder to the root of your target project:

```bash
cp -r /path/to/do-app-devcontainer/.devcontainer /path/to/your-project/
```

**What you get:**
- `devcontainer.json` - Container configuration with language features
- `docker-compose.yml` - All backing services (databases, queues, storage)
- `init.sh` - Git worktree support
- `post-create.sh` - Post-creation setup
- `tests/` - Service connectivity tests

**Do not modify** at this stage. The configuration is designed to work with any project structure.

---

## Phase 2: Configure Features Based on Project

Inspect the target project to determine what languages and services are needed, then update `devcontainer.json`.

### 2.1 Identify Required Languages

Check the project for:
- `package.json` → Node.js (already enabled by default)
- `requirements.txt` or `pyproject.toml` → Python (already enabled by default)
- `go.mod` → Go (uncomment in features)
- `Cargo.toml` → Rust (uncomment in features)
- `Gemfile` → Ruby (uncomment in features)
- `composer.json` → PHP (uncomment in features)

**Example**: Enable Go for a Go project:
```json
"features": {
  "ghcr.io/devcontainers/features/node:1": {},
  "ghcr.io/devcontainers/features/python:1": {},
  "ghcr.io/devcontainers/features/go:1": {},  // Uncommented
  ...
}
```

> **Note**: Keep Node.js and Python enabled even if not the primary language - they're often needed for tooling (npm scripts, AWS CLI, etc.).

### 2.2 Identify Required Services

Check the project's environment files (`.env`, `env-example`) and code for:
- Database connections → `postgres`, `mongo`, `mysql`
- Caching/sessions → `valkey`
- Message queues → `kafka`
- Object storage → `minio` (RustFS)
- Search → `opensearch`

Update `COMPOSE_PROFILES` in `devcontainer.json`:

```json
"containerEnv": {
  "COMPOSE_PROFILES": "app,postgres,minio"  // Add services as needed
}
```

**Available profiles:** `postgres`, `mongo`, `mysql`, `valkey`, `kafka`, `minio`, `opensearch`

### 2.3 Create DevContainer Environment File

Create an environment file for devcontainer use (e.g., `env-devcontainer.example`):

```bash
# Database - use service name, not localhost
DATABASE_URL=postgresql://postgres:password@postgres:5432/app

# Storage - use local RustFS/MinIO
STORAGE_PROVIDER=Spaces
SPACES_KEY_ID=rustfsadmin
SPACES_SECRET_KEY=rustfsadmin
SPACES_BUCKET_NAME=my-app-local
SPACES_ENDPOINT=http://minio:9000
SPACES_FORCE_PATH_STYLE=true
SPACES_REGION=us-east-1
```

**Key difference from production**: Inside Docker networks, use service names (`postgres`, `minio`) instead of `localhost`.

---

## Phase 3: Handle S3-Compatible Storage (RustFS vs Spaces)

Most services work identically between local and cloud. **Storage is the exception** - RustFS/MinIO requires different endpoint configuration than DigitalOcean Spaces, and buckets may need to be created.

### 3.1 The Problem

- **DigitalOcean Spaces**: Uses `https://{region}.digitaloceanspaces.com`, virtual-hosted-style URLs
- **RustFS/MinIO**: Uses `http://minio:9000`, path-style URLs, may need bucket creation

### 3.2 Environment Variable Pattern

**For Local Development (RustFS/MinIO):**
```bash
SPACES_ENDPOINT=http://minio:9000
SPACES_KEY_ID=rustfsadmin
SPACES_SECRET_KEY=rustfsadmin
SPACES_BUCKET_NAME=my-app-local
SPACES_FORCE_PATH_STYLE=true
SPACES_REGION=us-east-1  # Optional when endpoint is set
```

**For Production (DigitalOcean Spaces):**
```bash
SPACES_KEY_ID=your-access-key
SPACES_SECRET_KEY=your-secret-key
SPACES_BUCKET_NAME=my-app-production
SPACES_REGION=nyc3
# SPACES_ENDPOINT not set - uses default DO Spaces endpoint
```

### 3.3 Code Pattern: Auto-Detect and Auto-Create

Modify the storage service to:
1. Auto-detect if the endpoint is local (MinIO/RustFS)
2. Auto-create the bucket if it doesn't exist (local only)
3. Keep production behavior unchanged

**Detection Function (TypeScript/JavaScript):**
```typescript
private isLocalMinIOEndpoint(): boolean {
  const endpoint = process.env.SPACES_ENDPOINT || '';
  return (
    endpoint.startsWith('http://') ||
    endpoint.includes('localhost') ||
    endpoint.includes('minio') ||
    endpoint.includes('127.0.0.1')
  );
}
```

**Auto-Create Bucket (local only):**
```typescript
import { CreateBucketCommand } from '@aws-sdk/client-s3';

private async createBucket(): Promise<boolean> {
  if (!this.client) return false;

  try {
    await this.client.send(new CreateBucketCommand({ Bucket: this.bucketName }));
    console.log(`Bucket "${this.bucketName}" created successfully.`);
    return true;
  } catch (error: any) {
    // Bucket already exists - that's fine
    if (error.name === 'BucketAlreadyOwnedByYou' || error.name === 'BucketAlreadyExists') {
      return true;
    }
    console.error('Failed to create bucket:', error.message);
    return false;
  }
}
```

**Connection Check with Auto-Create (local only):**
```typescript
async checkConnection(): Promise<boolean> {
  try {
    // Try to access the bucket
    await this.client.send(new HeadBucketCommand({ Bucket: this.bucketName }));
    return true;
  } catch (error: any) {
    const bucketNotFound = error.name === 'NoSuchBucket' || error.name === 'NotFound';

    // Only auto-create for local MinIO/RustFS endpoints
    if (bucketNotFound && this.isLocalMinIOEndpoint()) {
      console.log(`Bucket not found. Creating "${this.bucketName}"...`);
      const created = await this.createBucket();
      if (created) {
        return true;  // Bucket created, connection successful
      }
    }

    // For production (DO Spaces), show error - bucket must be created manually
    return false;
  }
}
```

**S3 Client Configuration:**
```typescript
const client = new S3Client({
  endpoint: process.env.SPACES_ENDPOINT || `https://${region}.digitaloceanspaces.com`,
  region: process.env.SPACES_REGION || 'us-east-1',
  forcePathStyle: isLocalMinIOEndpoint(),  // true for MinIO, false for DO Spaces
  credentials: {
    accessKeyId: process.env.SPACES_KEY_ID!,
    secretAccessKey: process.env.SPACES_SECRET_KEY!,
  },
});
```

### 3.4 Summary

| Aspect | Local (RustFS/MinIO) | Production (DO Spaces) |
|--------|---------------------|------------------------|
| Endpoint | `http://minio:9000` | `https://{region}.digitaloceanspaces.com` |
| Path Style | `true` | `false` |
| Bucket Creation | Auto-create if missing | Manual (dashboard or CLI) |
| Credentials | `rustfsadmin/rustfsadmin` | Your DO Spaces keys |

---

## Additional Information

### Opening in DevContainer

1. Install the **Dev Containers** extension in your IDE (VS Code, Cursor, etc.)
2. Open your project folder
3. Run Command Palette → **"Dev Containers: Open Folder in Container..."**

### Git Worktree Support

This devcontainer has built-in worktree support. The `init.sh` script automatically detects and mounts the git common directory.

```bash
# Create a worktree
git worktree add ../feature-x origin/feature-x

# Open in VS Code/Cursor - devcontainer just works
```

### Dynamic Service Start

Since Docker-out-of-Docker is enabled, start additional services without rebuilding:

```bash
docker compose -f .devcontainer/docker-compose.yml --profile mongo up -d
```

### Testing Services

```bash
# Test all running services
.devcontainer/tests/run-all-tests.sh --all

# Test specific services
.devcontainer/tests/run-all-tests.sh postgres minio

# List available tests
.devcontainer/tests/run-all-tests.sh --list
```

### Container Shutdown

By default, containers stop when you close the IDE (`shutdownAction: stopCompose`). To keep them running, change to `"none"` in `devcontainer.json`.

---

## Architecture

![Dev Container Architecture](images/devcontainer-architecture.svg)

All you need on your machine is Docker (or any Docker-compatible runtime). The devcontainer provides all languages, tools, and services.
