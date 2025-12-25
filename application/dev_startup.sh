#!/bin/bash
#
# Next.js / Node.js Development Startup Script
#
# Features:
# - Handles npm install with legacy-peer-deps for compatibility
# - Auto-detects package.json changes and reinstalls (polls every GITHUB_SYNC_INTERVAL seconds)
# - Falls back to hard rebuild if install fails
# - Runs the dev server (best for hot reload / iteration)
# - Tip: for faster dev builds, set your package.json dev script to use Turbopack:
#     "dev": "next dev --turbopack"
#
# For subfolder apps, set APP_DIR in your app spec:
#   APP_DIR=/workspaces/app/application
#

set -e

APP_DIR="/workspaces/app/application"

# Change to app directory (defaults to current dir, set APP_DIR for subfolders)
APP_DIR="${APP_DIR:-$(pwd)}"
cd "$APP_DIR" || exit 1

# Create .npmrc for peer dependency compatibility
echo "legacy-peer-deps=true" > .npmrc

# Track if we need to reinstall
HASH_FILE=".deps_hash"
CURRENT_HASH=$(sha256sum package.json 2>/dev/null | cut -d' ' -f1 || echo "none")
STORED_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")

install_deps() {
    echo "Installing dependencies..."
    if ! npm install; then
        echo "Standard install failed, trying hard rebuild..."
        rm -rf node_modules package-lock.json
        npm install
    fi
    echo "$CURRENT_HASH" > "$HASH_FILE"
}

# Install if hash changed or node_modules missing
if [ "$CURRENT_HASH" != "$STORED_HASH" ] || [ ! -d "node_modules" ]; then
    install_deps
fi

start_server() {
    echo "Starting Next.js dev server..."
    # Start in its own process group so stop_server can reliably kill the
    # process that actually owns port 8080 (Next.js often spawns children).
    setsid npm run dev -- --hostname 0.0.0.0 --port 8080 >/tmp/nextjs-dev.log 2>&1 &
    echo $! > .server_pgid
}

stop_server() {
    if [ -f ".server_pgid" ]; then
        local pgid
        pgid=$(cat .server_pgid 2>/dev/null || echo "")
        if [ -n "$pgid" ]; then
            # Negative PID = kill the entire process group.
            kill -- "-$pgid" 2>/dev/null || true
        fi
        rm -f .server_pgid
    fi
}

SYNC_INTERVAL="${GITHUB_SYNC_INTERVAL:-15}"
SYNC_INTERVAL="${SYNC_INTERVAL%.*}"
if [ -z "$SYNC_INTERVAL" ]; then
    SYNC_INTERVAL="15"
fi

trap 'stop_server; exit 0' INT TERM

start_server

# Loop forever:
# - If package.json changes: npm install + restart dev server
# - If server dies: restart it
while true; do
    sleep "$SYNC_INTERVAL"

    # Restart if dev server died
    if [ -f ".server_pgid" ]; then
        pid=$(cat .server_pgid 2>/dev/null || echo "")
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            echo "Dev server exited; restarting..."
            rm -f .server_pgid
            start_server
        fi
    fi

    # Check for dependency changes
    CURRENT_HASH=$(sha256sum package.json 2>/dev/null | cut -d' ' -f1 || echo "none")
    STORED_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" != "$STORED_HASH" ]; then
        echo "package.json changed; installing deps and restarting dev server..."
        install_deps
        stop_server
        start_server
    fi
done