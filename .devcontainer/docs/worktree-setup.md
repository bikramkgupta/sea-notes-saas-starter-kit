# Git Worktrees with Dev Containers

This guide explains how to use Git worktrees with this devcontainer setup.

## What are Git Worktrees?

Git worktrees let you check out multiple branches simultaneously in separate directories. Instead of stashing or committing to switch branches, you work on each branch in its own folder.

```
my-project/
├── .bare/           # Shared git repository data
├── main/            # Worktree for main branch
├── feature-x/       # Worktree for feature-x branch
└── bugfix-y/        # Worktree for bugfix-y branch
```

## The Problem with Dev Containers

Standard dev containers fail with worktrees because:

1. **No `.git` folder**: Worktrees have a `.git` *file* (not folder) that points to the shared `.bare` directory
2. **Absolute paths**: The `.git` file contains an absolute path like `/Users/you/project/.bare`
3. **Mount mismatch**: When the container mounts the worktree, the `.bare` path doesn't exist inside the container

Result: Git commands fail inside the container because they can't find the repository data.

## The Solution

This devcontainer includes an `init.sh` script that automatically:

1. **Detects the git common directory** (the `.bare` folder) using `git rev-parse --git-common-dir`
2. **Mounts it inside the container** at the same absolute path via `docker-compose.yml`
3. **Sets `COMPOSE_PROJECT_NAME`** to the folder name so docker compose works correctly

This happens automatically via the `initializeCommand` in `devcontainer.json`.

## Setting Up a Worktree Repository

### Initial Setup (One-time)

If you're starting fresh or converting an existing repo:

```bash
# Clone as a bare repository
git clone --bare git@github.com:you/repo.git .bare

# Create a .git file pointing to .bare
echo "gitdir: ./.bare" > .git

# Configure fetch for all remotes
git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

# Fetch all branches
git fetch origin

# Create your first worktree (usually main)
git worktree add main main
```

Your structure should look like:
```
repo/
├── .bare/     # The actual git data
├── .git       # File pointing to .bare
└── main/      # Your first worktree
```

### Creating New Worktrees

```bash
# From the repo root (where .bare is)
git worktree add feature-x origin/feature-x

# Or create a new branch
git worktree add -b new-feature main
```

### Opening in Dev Container

1. Open the worktree folder (e.g., `feature-x/`) in VS Code or Cursor
2. When prompted, choose "Reopen in Container"
3. The `init.sh` script runs automatically and sets up git access

### Removing Worktrees

```bash
# From the repo root
git worktree remove feature-x

# Delete the branch if no longer needed
git branch -d feature-x
```

## How It Works Internally

### The `init.sh` Script

Located at `.devcontainer/init.sh`, this script:

```bash
# Gets the absolute path to .bare
gitdir="$(git rev-parse --git-common-dir)"

# Gets the folder name for COMPOSE_PROJECT_NAME
project_name="$(basename "$PWD")"

# Writes both to .env for docker-compose
echo "COMPOSE_PROJECT_NAME=$project_name" >> .devcontainer/.env
echo "GIT_COMMON_DIR=$gitdir" >> .devcontainer/.env
```

### The Docker Compose Mount

In `docker-compose.yml`:

```yaml
volumes:
  - ..:/workspaces/app:cached
  - ${GIT_COMMON_DIR}:${GIT_COMMON_DIR}:cached  # Mounts .bare at same path
```

This ensures `/Users/you/project/.bare` exists at the same path inside the container.

### Why COMPOSE_PROJECT_NAME Matters

Docker Compose uses the project name to:
- Prefix container names (e.g., `main-app-1`, `feature-x-postgres-1`)
- Namespace volumes (so each worktree has isolated data)
- Make `docker compose ps` work correctly inside the container

Without it explicitly set, containers from different worktrees can collide.

## Multiple Worktrees Running Simultaneously

This setup supports running multiple worktrees at once:

1. **Dynamic ports**: Services use `127.0.0.1:0:PORT`, letting Docker assign free ports
2. **Unique project names**: Each worktree gets its own container/volume namespace
3. **Isolated data**: Each worktree has its own database volumes

### Finding Assigned Ports

```bash
# List all containers with ports
docker compose ps

# Get specific port
docker compose port postgres 5432
docker compose port minio 9000
```

Inside the container, use service names directly:
- `postgres:5432`
- `minio:9000`
- `mongo:27017`

## Troubleshooting

### Git commands fail inside container

**Symptom**: `fatal: not a git repository`

**Check**: Verify `.bare` is mounted correctly:
```bash
ls -la $GIT_COMMON_DIR
```

**Fix**: If the path doesn't exist, the `init.sh` may not have run. Try rebuilding:
```
Cmd/Ctrl + Shift + P -> "Dev Containers: Rebuild Container"
```

### Docker compose doesn't show containers

**Symptom**: `docker compose ps` shows nothing

**Check**: Verify `COMPOSE_PROJECT_NAME` is set:
```bash
echo $COMPOSE_PROJECT_NAME
cat .devcontainer/.env | grep COMPOSE_PROJECT_NAME
```

**Fix**: The project name should match your folder. If not, rebuild the container.

### Port conflicts

**Symptom**: Container fails to start due to port in use

**Cause**: This shouldn't happen with dynamic ports (`127.0.0.1:0:PORT`)

**Check**: Verify your `docker-compose.yml` uses dynamic port binding:
```yaml
ports:
  - "127.0.0.1:0:5432"  # Correct - dynamic
  - "5432:5432"          # Wrong - fixed port
```

### Containers from wrong worktree

**Symptom**: Commands affect containers from a different worktree

**Check**: Verify you're in the right directory and `COMPOSE_PROJECT_NAME` matches:
```bash
pwd
echo $COMPOSE_PROJECT_NAME
```

## Daily Workflow Summary

1. **Start work**: Open worktree folder in IDE, reopen in container
2. **During work**: Git commands work normally, use service names for connections
3. **Switch branches**: Open a different worktree folder (or create one)
4. **End work**: Close IDE window (containers stop automatically with `shutdownAction: stopCompose`)
5. **Cleanup**: `git worktree remove <folder>` when done with a branch
