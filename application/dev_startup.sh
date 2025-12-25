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
        if ! npm run build; then
            echo "ERROR: Build failed!"
            return 1
        fi
        
        # Verify build completed successfully
        if [ ! -d ".next" ]; then
            echo "ERROR: Build completed but .next directory not found!"
            return 1
        fi
        
        echo "$current_hash" > "$BUILD_HASH_FILE"
        echo "Build completed successfully"
        return 0
    fi
    return 1
}

start_server() {
    echo "Starting Next.js production server..."
    echo "Command: npm run start -- --hostname 0.0.0.0 --port 8080"
    
    # Verify build exists before starting
    if [ ! -d ".next" ]; then
        echo "ERROR: .next build directory not found. Forcing rebuild..."
        rm -f .build_hash
        build_if_needed || {
            echo "ERROR: Build failed. Cannot start server."
            return 1
        }
    fi
    
    # Start in its own process group so stop_server can reliably kill the
    # process that actually owns port 8080 (npm/next may spawn children).
    # Use setsid to create new session, then get the actual process group ID
    setsid npm run start -- --hostname 0.0.0.0 --port 8080 >/tmp/nextjs-start.log 2>&1 &
    local setsid_pid=$!
    
    # Get the process group ID (PGID) of the setsid process
    # This is what we need to kill the entire process group later
    sleep 0.5  # Give setsid a moment to start
    local pgid
    pgid=$(ps -o pgid= -p "$setsid_pid" 2>/dev/null | tr -d ' ' || echo "")
    
    if [ -z "$pgid" ]; then
        # Fallback: use setsid_pid as PGID (setsid creates a new process group with itself as leader)
        pgid=$setsid_pid
    fi
    
    echo "$pgid" > .server_pgid
    echo "Server started with PGID: $pgid (setsid PID: $setsid_pid)"
    
    # Wait a few seconds and check if server is actually running
    sleep 3
    
    # Check if any process in the process group is still running
    local process_alive=false
    if kill -0 "$setsid_pid" 2>/dev/null; then
        process_alive=true
    elif command -v pgrep >/dev/null 2>&1; then
        # Check if any process with this PGID is running
        if pgrep -g "$pgid" >/dev/null 2>&1; then
            process_alive=true
        fi
    fi
    
    # Also check if port 8080 is listening (most reliable indicator)
    local port_listening=false
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :8080 >/dev/null 2>&1; then
            port_listening=true
            echo "Server is listening on port 8080"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":8080 "; then
            port_listening=true
            echo "Server is listening on port 8080"
        fi
    fi
    
    if [ "$process_alive" = "true" ] || [ "$port_listening" = "true" ]; then
        echo "Server appears to be running (process: $process_alive, port: $port_listening)"
    else
        echo "ERROR: Server process died immediately after start!"
        echo "Last 30 lines of error log:"
        tail -30 /tmp/nextjs-start.log 2>/dev/null || echo "Error log not found"
        return 1
    fi
    
    return 0
}

stop_server() {
    if [ -f ".server_pgid" ]; then
        local pgid
        pgid=$(cat .server_pgid 2>/dev/null || echo "")
        if [ -n "$pgid" ]; then
            echo "Stopping server (PGID: $pgid)..."
            # Kill the entire process group
            kill -- "-$pgid" 2>/dev/null || true
            # Wait a moment for graceful shutdown
            sleep 2
            # Force kill if still running
            kill -9 -- "-$pgid" 2>/dev/null || true
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
echo "=== Initial Setup ==="
echo "Working directory: $(pwd)"
echo "Package.json exists: $([ -f package.json ] && echo 'YES' || echo 'NO')"

install_deps_if_needed || {
    echo "WARNING: Dependency installation had issues, but continuing..."
}

build_if_needed || {
    echo "ERROR: Initial build failed. Cannot start server without a build."
    echo "Will retry build on next cycle..."
    # Don't exit - let the loop retry
}

# Only start server if build exists
if [ -d ".next" ]; then
    if ! start_server; then
        echo "ERROR: Failed to start server initially. Will retry in next cycle."
    fi
else
    echo "WARNING: No .next build directory. Server will start after build completes."
fi

echo "=== Entering monitoring loop ==="

while true; do
    sleep "$SYNC_INTERVAL"

    # Restart if server died
    if [ -f ".server_pgid" ]; then
        pgid=$(cat .server_pgid 2>/dev/null || echo "")
        if [ -n "$pgid" ]; then
            # Check if server is still running using multiple methods
            local is_alive=false
            
            # Method 1: Check if any process in the process group is running
            if command -v pgrep >/dev/null 2>&1; then
                if pgrep -g "$pgid" >/dev/null 2>&1; then
                    is_alive=true
                fi
            fi
            
            # Method 2: Check if port 8080 is listening (most reliable)
            if [ "$is_alive" = "false" ]; then
                if command -v lsof >/dev/null 2>&1; then
                    if lsof -i :8080 >/dev/null 2>&1; then
                        is_alive=true
                    fi
                elif command -v netstat >/dev/null 2>&1; then
                    if netstat -tln 2>/dev/null | grep -q ":8080 "; then
                        is_alive=true
                    fi
                fi
            fi
            
            # Method 3: Check if PGID process itself is alive (fallback)
            if [ "$is_alive" = "false" ] && kill -0 "$pgid" 2>/dev/null; then
                is_alive=true
            fi
            
            if [ "$is_alive" = "false" ]; then
                echo "Production server exited; restarting..."
                echo "Last 30 lines of error log:"
                tail -30 /tmp/nextjs-start.log 2>/dev/null || echo "Error log not found"
                rm -f .server_pgid
                if ! start_server; then
                    echo "ERROR: Failed to start server. Will retry on next cycle."
                    # Don't remove .server_pgid here so we know to retry
                fi
            fi
        else
            # No PGID file but we should have a server running
            echo "WARNING: .server_pgid file missing. Starting server..."
            start_server || echo "ERROR: Failed to start server."
        fi
    else
        # No server running at all - check if port is in use (maybe from previous run)
        local port_in_use=false
        if command -v lsof >/dev/null 2>&1; then
            if lsof -i :8080 >/dev/null 2>&1; then
                port_in_use=true
                echo "WARNING: Port 8080 is in use but no .server_pgid file. This might be a stale process."
            fi
        fi
        
        if [ "$port_in_use" = "false" ]; then
            echo "WARNING: No server process found. Starting server..."
            start_server || echo "ERROR: Failed to start server."
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


