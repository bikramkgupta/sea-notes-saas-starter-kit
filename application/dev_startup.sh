#!/bin/bash
#
# Next.js "Optimized" Startup Script (no HMR)
#
# Goal:
# - Avoid `next dev` (HMR) for users who want to test production-style performance.
# - Run `npm install` (when package.json changes), then `npm run build`, then `npm run start`.
# - Poll for changes after GitHub sync and rebuild/restart when needed.
#
# Notes:
# - This is NOT hot module reloading. It is “rebuild & restart on change”.
# - Next.js production server requires a prior build (`next build`).
#

set -euo pipefail

# Change to application directory (where package.json is located)
cd /workspaces/app/application || exit 1

echo "legacy-peer-deps=true" > .npmrc

DEPS_HASH_FILE=".deps_hash"
BUILD_HASH_FILE=".build_hash"

compute_deps_hash() {
    sha256sum package.json 2>/dev/null | cut -d' ' -f1 || echo "none"
}

install_deps_if_needed() {
    local current_deps_hash stored_deps_hash
    current_deps_hash=$(compute_deps_hash)
    stored_deps_hash=$(cat "$DEPS_HASH_FILE" 2>/dev/null || echo "")

    if [ "$current_deps_hash" != "$stored_deps_hash" ] || [ ! -d "node_modules" ]; then
        echo "Installing dependencies..."
        if ! npm install; then
            echo "Standard install failed, trying hard rebuild..."
            rm -rf node_modules package-lock.json
            npm install
        fi
        echo "$current_deps_hash" > "$DEPS_HASH_FILE"
        return 0
    fi
    return 1
}

compute_build_hash() {
    # Include src/ plus common Next.js config files that affect output
    local parts=""

    if [ -d "src" ]; then
        local src_files
        src_files=$(find src -type f 2>/dev/null | sort || true)
        if [ -n "$src_files" ]; then
            local src_hash
            src_hash=$(echo "$src_files" | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "")
            parts="${parts}${src_hash}"
        fi
    fi

    for f in next.config.{js,mjs,ts} tsconfig.json package.json; do
        if [ -f "$f" ]; then
            parts="${parts}$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || true)"
        fi
    done

    if [ -n "$parts" ]; then
        echo -n "$parts" | sha256sum | cut -d' ' -f1
    else
        echo "none"
    fi
}

build_if_needed() {
    local current_hash stored_hash
    current_hash=$(compute_build_hash)
    stored_hash=$(cat "$BUILD_HASH_FILE" 2>/dev/null || echo "")

    if [ "$current_hash" != "$stored_hash" ] || [ ! -d ".next" ]; then
        echo "Building Next.js app (production)..."
        npm run build
        echo "$current_hash" > "$BUILD_HASH_FILE"
        return 0
    fi
    return 1
}

start_server() {
    echo "Starting Next.js production server..."
    # Start in its own process group so stop_server can reliably kill the
    # process that actually owns port 8080 (npm/next may spawn children).
    setsid npm run start -- --hostname 0.0.0.0 --port 8080 >/tmp/nextjs-start.log 2>&1 &
    echo $! > .server_pgid
}

stop_server() {
    if [ -f ".server_pgid" ]; then
        local pgid
        pgid=$(cat .server_pgid 2>/dev/null || echo "")
        if [ -n "$pgid" ]; then
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

# Initial setup
install_deps_if_needed || true
build_if_needed || true
start_server

while true; do
    sleep "$SYNC_INTERVAL"

    # Restart if server died
    if [ -f ".server_pgid" ]; then
        pid=$(cat .server_pgid 2>/dev/null || echo "")
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            echo "Production server exited; restarting..."
            rm -f .server_pgid
            start_server
        fi
    fi

    # If deps changed, install (and we'll rebuild/restart below if needed)
    deps_changed=false
    if install_deps_if_needed; then
        deps_changed=true
    fi

    # If build changed (or deps changed), rebuild and restart
    build_changed=false
    if build_if_needed; then
        build_changed=true
    fi

    if [ "$deps_changed" = "true" ] || [ "$build_changed" = "true" ]; then
        echo "Changes detected; restarting production server..."
        stop_server
        start_server
    fi
done


