sudo tee /usr/local/bin/manual_start_gpu.sh > /dev/null <<'EOF'
#!/bin/bash

set -Eeuo pipefail
shopt -s inherit_errexit

echo "========================================"
echo "MANUAL MINER START SCRIPT"
echo "========================================"

# -------------------------------------------------
# HARDCODED CONFIGURATION
# -------------------------------------------------
echo "[init] Loading configuration..."

# Hardcoded paths
MINER_CONF="/home/user/miner.conf"
API_CONF="/home/user/api.conf"
CFG_FILE="/home/user/rig-gpu.conf"
BASE_DIR="/home/user/miners"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[init] MINER_CONF=$MINER_CONF"
echo "[init] API_CONF=$API_CONF"
echo "[init] CFG_FILE=$CFG_FILE"
echo "[init] BASE_DIR=$BASE_DIR"
echo "[init] SCRIPT_DIR=$SCRIPT_DIR"

mkdir -p "$BASE_DIR"

# -------------------------------------------------
# Check config files exist
# -------------------------------------------------
[[ -f "$CFG_FILE" ]] || {
    echo "Missing rig config: $CFG_FILE"
    exit 1
}

[[ -f "$MINER_CONF" ]] || {
    echo "Missing miner.conf: $MINER_CONF"
    exit 1
}

# -------------------------------------------------
# Source libraries
# -------------------------------------------------
for f in \
    "$SCRIPT_DIR/lib/00-get_rig_conf.sh" \
    "$SCRIPT_DIR/lib/01-miner_install.sh" \
    "$SCRIPT_DIR/lib/02-load_configs.sh" \
    "$SCRIPT_DIR/lib/03-cpu_threads.sh" \
    "$SCRIPT_DIR/lib/04-algo_config.sh"
do
    [[ -f "$f" ]] || { echo "Missing include: $f"; exit 1; }
    source "$f"
done

# -------------------------------------------------
# Get OC settings from rig.conf
# -------------------------------------------------
APPLY_OC=$(get_rig_conf "APPLY_OC" "0")
RESET_OC=$(get_rig_conf "RESET_OC" "0")

# Remove quotes if present
APPLY_OC="${APPLY_OC//\"/}"
RESET_OC="${RESET_OC//\"/}"

# Convert to lowercase for comparison
APPLY_OC="${APPLY_OC,,}"
RESET_OC="${RESET_OC,,}"

# Default to false if empty
: "${APPLY_OC:=false}"
: "${RESET_OC:=false}"

echo "[oc] APPLY_OC: $APPLY_OC"
echo "[oc] RESET_OC: $RESET_OC"

# ---------------------------------------------------------
# API SETTINGS - from hardcoded API_CONF
# ---------------------------------------------------------
if [[ ! -f "$API_CONF" ]]; then
    echo "[api] WARNING: $API_CONF not found, API disabled"
    API_HOST="127.0.0.1"
    API_PORT=0
else
    echo "[api] Loading API settings from $API_CONF"
    source "$API_CONF"
    
    MINER_UPPER=$(echo "$MINER_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    
    MINER_API_PORT_VAR="${MINER_UPPER}_API_PORT"
    if [[ -n "${!MINER_API_PORT_VAR:-}" ]]; then
        API_PORT="${!MINER_API_PORT_VAR}"
        echo "[api] Found specific API_PORT: $MINER_API_PORT_VAR=$API_PORT"
    else
        : "${API_PORT:=0}"
        echo "[api] Using generic API_PORT: $API_PORT"
    fi
    
    MINER_API_HOST_VAR="${MINER_UPPER}_API_HOST"
    if [[ -n "${!MINER_API_HOST_VAR:-}" ]]; then
        API_HOST="${!MINER_API_HOST_VAR}"
        echo "[api] Found specific API_HOST: $MINER_API_HOST_VAR=$API_HOST"
    else
        : "${API_HOST:=127.0.0.1}"
        echo "[api] Using generic API_HOST: $API_HOST"
    fi
fi

echo "[api] Final API settings for $MINER_NAME:"
echo "[api]   API_HOST=$API_HOST"
echo "[api]   API_PORT=$API_PORT"

# ---------------------------------------------------------
# MINER-SPECIFIC API COMMAND GENERATION
# ---------------------------------------------------------
add_api_flags() {
    local miner_name="$1"
    local api_host="$2"
    local api_port="$3"
    local current_args="$4"
    
    if [[ "$api_port" -eq 0 ]]; then
        echo "$current_args"
        return
    fi
    
    case "$miner_name" in
        "xmrig"|"xmrig-cpu"|"xmrig-gpu")
            echo "$current_args --http-host=$api_host --http-port=$api_port"
            ;;
        "rigel")
            echo "$current_args --api-bind $api_host:$api_port"
            ;;
        "srbminer"|"srbminer-cpu"|"srbminer-gpu"|"srbminer-multi")
            echo "$current_args --api-enable --api-port $api_port"
            ;;
        "lolminer")
            echo "$current_args --apiport $api_port --apihost $api_host"
            ;;
        "wildrig")
            echo "$current_args --api-port $api_port"
            ;;
        "gminer")
            echo "$current_args --api $api_port"
            ;;
        "bzminer")
            echo "$current_args --http_port $api_port --http_address $api_host"
            ;;
        "onezerominer")
            echo "$current_args --api-port $api_port"
            ;;
        "t-rex")
            echo "$current_args --api-bind $api_host:$api_port"
            ;;
        "teamredminer")
            echo "$current_args --api_listen=$api_host:$api_port"
            ;;
        "nbminer")
            echo "$current_args --api $api_host:$api_port"
            ;;
        *)
            echo "$current_args"
            ;;
    esac
}

# ---------------------------------------------------------
# FINAL PLACEHOLDER SUBSTITUTION
# ---------------------------------------------------------

# CPU threads
if [[ -n "$AUTOFILL_CPU" ]]; then
    ARGS="${ARGS//%CPU_THREADS%/$AUTOFILL_CPU}"
else
    ARGS="${ARGS//%CPU_THREADS%/$CPU_THREADS}"
fi

# Warthog target
if [[ -n "$WARTHOG_TARGET" ]]; then
    ARGS="${ARGS//%WARTHOG_TARGET%/$WARTHOG_TARGET}"
fi

# Replace %WORKER_NAME% placeholder in ARGS, WALLET, PASS, POOL
ARGS="${ARGS//%WORKER_NAME%/$WORKER_NAME}"
WALLET="${WALLET//%WORKER_NAME%/$WORKER_NAME}"
PASS="${PASS//%WORKER_NAME%/$WORKER_NAME}"
POOL="${POOL//%WORKER_NAME%/$WORKER_NAME}"

# Add miner-specific API flags
if [[ "$API_PORT" -gt 0 ]]; then
        ARGS=$(add_api_flags "$MINER_NAME" "$API_HOST" "$API_PORT" "$ARGS")
fi

# Load from rig.conf
SCREEN_NAME=$(get_rig_conf "SCREEN_NAME" "0")

# If SCREEN_NAME is empty (""), ignore and use miner name
if [[ -z "$SCREEN_NAME" ]]; then
    SCREEN_NAME="$MINER_NAME"
fi

echo "========================================"
echo "STARTUP CONFIGURATION SUMMARY"
echo "========================================"
echo "Miner Name:      $MINER_NAME"
echo "Screen Session:  $SCREEN_NAME"
echo "Worker Name:     $WORKER_NAME"
echo "API:             $API_HOST:$API_PORT"
echo "Wallet:          $WALLET"
echo "Pool:            $POOL"
echo "Apply GPU OC:    $APPLY_OC"
echo "Reset GPU on Stop: $RESET_OC"
echo "========================================"

# ---------------------------------------------------------
# Get START_CMD from library function
# ---------------------------------------------------------
START_CMD=$(get_start_cmd "$MINER_NAME")
echo "[debug] START_CMD: $START_CMD"

# ---------------------------------------------------------
# API HEALTH CHECK FUNCTION
# ---------------------------------------------------------
check_api_health() {
    if [[ "$API_PORT" -eq 0 ]]; then
        return 0
    fi
    
    # Check if API port is listening
    if timeout 2 bash -c "echo > /dev/tcp/$API_HOST/$API_PORT" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------
# START MINER FUNCTION
# ---------------------------------------------------------
start_miner() {
    # Check if miner is already running
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "[$(date)] Screen session exists for $SCREEN_NAME - checking if miner is alive..."
        
        local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
        if [[ -f "$pid_file" ]]; then
            local miner_pid=$(cat "$pid_file")
            
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "[$(date)] Miner already running in screen session: $SCREEN_NAME"
                echo "[$(date)] To view: sudo screen -r $SCREEN_NAME"
                echo "[$(date)] PID: $miner_pid"
                return 0
            else
                echo "[$(date)] Miner process is dead but screen session exists - cleaning up..."
                screen -S "$SCREEN_NAME" -X quit 2>/dev/null || true
                rm -f "$pid_file"
                echo "[$(date)] Starting fresh miner after cleanup..."
            fi
        else
            echo "[$(date)] Screen session exists but no PID file found - cleaning up..."
            screen -S "$SCREEN_NAME" -X quit 2>/dev/null || true
            echo "[$(date)] Starting fresh miner after cleanup..."
        fi
    fi
    
    # Start fresh miner
    
    # Apply GPU OC's if configured
    if [[ "${APPLY_OC,,}" == "true" ]]; then
        echo "[$(date)] Applying GPU clocks..."
        /usr/local/bin/gpu_apply_ocs.sh
    fi
    
    echo "[$(date)] Starting $SCREEN_NAME..."
    echo "[$(date)] API: $API_HOST:$API_PORT"
    echo "[$(date)] Full Command: $START_CMD"
    
    # Create PID file directory
    mkdir -p /tmp/miner_pids
    
    # Start in screen session with PID tracking
    screen -dmS "$SCREEN_NAME" bash -c \
        'echo "Miner starting at $(date)"; \
         echo "API: '"$API_HOST:$API_PORT"'"; \
         echo "$$" > "'"/tmp/${SCREEN_NAME}_miner.pid"'"; \
         trap '\''echo "Miner exiting at $(date)"; rm -f "'"/tmp/${SCREEN_NAME}_miner.pid"'"'\'' EXIT; \
         '"$START_CMD"
    
    # Wait for PID file creation
    sleep 3
    
    # Verify startup
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "[$(date)] Miner started in screen session: $SCREEN_NAME"
        
        if [[ -f "/tmp/${SCREEN_NAME}_miner.pid" ]]; then
            local miner_pid=$(cat "/tmp/${SCREEN_NAME}_miner.pid")
            echo "[$(date)] Miner process PID: $miner_pid"
        fi
        
        # Wait for API to come up if enabled
        if [[ "$API_PORT" -gt 0 ]]; then
            echo "[$(date)] Waiting for API to start (max 30 seconds)..."
            local max_wait=30
            local waited=0
            
            while [[ $waited -lt $max_wait ]]; do
                if check_api_health; then
                    echo "[$(date)] API is up and running"
                    break
                fi
                sleep 1
                ((waited++))
            done
            
            if [[ $waited -ge $max_wait ]]; then
                echo "[$(date)] WARNING: API did not respond after $max_wait seconds"
            fi
        else
            echo "[$(date)] API disabled, skipping health check"
        fi
        
        echo "[$(date)] ARGS/OCS: $ARGS"
        echo "[$(date)] To view miner output: sudo screen -r $SCREEN_NAME"
        echo "========================================"
        echo "MINER STARTED SUCCESSFULLY"
        echo "========================================"
        return 0
    else
        echo "[$(date)] ERROR: Failed to start screen session!"
        
        if [[ -f "/tmp/${SCREEN_NAME}_miner.pid" ]]; then
            local miner_pid=$(cat "/tmp/${SCREEN_NAME}_miner.pid")
            echo "[$(date)] Found PID file with PID: $miner_pid"
            
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "[$(date)] Process $miner_pid is running but no screen session"
                echo "[$(date)] You may need to kill it manually: kill $miner_pid"
            fi
        fi
        
        return 1
    fi
}

# ---------------------------------------------------------
# MAIN START LOGIC
# ---------------------------------------------------------
echo "Starting miner in 3 seconds... (Press Ctrl+C to cancel)"
sleep 3
start_miner
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/manual_start_gpu.sh