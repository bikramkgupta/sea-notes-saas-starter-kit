#!/bin/bash
# Git worktree support for devcontainers
# This script appends GIT_COMMON_DIR to .env for docker-compose variable interpolation
# Reference: https://stackoverflow.com/questions/77478945/git-worktrees-in-vscode-devcontainer

gitdir="$(git rev-parse --git-common-dir)"
case $gitdir in
    /*) ;;
    *) gitdir="$PWD/$gitdir"
esac

# Get the folder name for COMPOSE_PROJECT_NAME
# Docker Compose inside devcontainers won't display containers (on host or inside)
# unless COMPOSE_PROJECT_NAME is explicitly set to the folder name
project_name="$(basename "$PWD")"

# Remove old GIT_COMMON_DIR and COMPOSE_PROJECT_NAME lines if they exist
# Using sed -i.bak for macOS/Linux compatibility
sed -i.bak '/^GIT_COMMON_DIR=/d' ".devcontainer/.env" 2>/dev/null || true
sed -i.bak '/^COMPOSE_PROJECT_NAME=/d' ".devcontainer/.env" 2>/dev/null || true
sed -i.bak '/^# COMPOSE_PROJECT_NAME is required/d' ".devcontainer/.env" 2>/dev/null || true
rm -f ".devcontainer/.env.bak" 2>/dev/null || true

# Ensure newline before appending (in case .env doesn't end with one)
[ -n "$(tail -c 1 ".devcontainer/.env" 2>/dev/null)" ] && echo "" >> ".devcontainer/.env"

# Append COMPOSE_PROJECT_NAME with explanatory comment
echo "# COMPOSE_PROJECT_NAME is required for docker compose to work inside devcontainers" >> ".devcontainer/.env"
echo "COMPOSE_PROJECT_NAME=$project_name" >> ".devcontainer/.env"
echo "GIT_COMMON_DIR=$gitdir" >> ".devcontainer/.env"
