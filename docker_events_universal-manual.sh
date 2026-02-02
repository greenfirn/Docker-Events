sudo tee /usr/local/bin/docker_events_universal.sh > /dev/null <<'EOF'
#!/bin/bash

# ===================================================================
# DEFAULT SETTINGS (Fallback when config files don't exist)
# This script is meant to be run via systemd service, but if the config files
# specified in the service don't exist, these default settings are used.
# ===================================================================

# === DEFAULT CPU THREADS AND AFFINITY ===
MINER_NAME="xmrig"
ALGO="rx/0"

TOTAL_THREADS=$(nproc 2>/dev/null || echo 4)
CPU_THREADS=$((TOTAL_THREADS - 1))

AUTOFILL_CPU=""

if [[ "$MINER_NAME" == "xmrig" && "$ALGO" == "rx/0" ]]; then
    RX_THREADS=-1

    if [[ "$TOTAL_THREADS" -eq 32 ]]; then
        RX_THREADS=31
        RX_CORES=(0 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31)
    elif [[ "$TOTAL_THREADS" -eq 24 ]]; then
        RX_THREADS=23
        RX_CORES=(0 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23)
    fi

    if [[ "$RX_THREADS" -ne -1 ]]; then
        BITMASK=0
        for core in "${RX_CORES[@]}"; do
            (( BITMASK |= (1 << core) ))
        done
        RX_MASK=$(printf "0x%X" "$BITMASK")
        AUTOFILL_CPU="$RX_THREADS --cpu-affinity=$RX_MASK"
    fi
fi

# === DEFAULT MINER CONFIG ===
APPLY_OC="false"
RESET_OC="false"

START_CMD="/home/user/miners/xmrig/current/xmrig"

# WORKER_NAME as hostname capital x,t,s
if [[ -f "/etc/hostname" ]]; then
    WORKER_NAME="$(cat /etc/hostname)"
    WORKER_NAME="${WORKER_NAME//x/X}"
    WORKER_NAME="${WORKER_NAME//t/T}"
    WORKER_NAME="${WORKER_NAME//s/S}"
else
    WORKER_NAME="rig1"
fi

WALLET="wallet-address"

POOL="pool.supportxmr.com:9000"

PASS="x"

# Using placeholders for substitution
ARGS="-a rx/0 -k -t %CPU_THREADS% --randomx-1gb-pages --huge-pages -p %WORKER_NAME% -u %WALLET% --tls -o %POOL%"

SCREEN_NAME="cpu"

TARGET_NAME=""
TARGET_IMAGE=""

API_HOST="127.0.0.1"
API_PORT=18080

WARTHOG_TARGET=""

# ===================================================================
# END DEFAULT SETTINGS
# ===================================================================

set -Eeuo pipefail
shopt -s inherit_errexit

# ---------------------------------------------------------
# GLOBAL VARIABLES
# ---------------------------------------------------------
SHUTDOWN_REQUESTED=0
: "${DOCKER_RUNNING_CONFIRM_LOOPS:=2}"

# ---------------------------------------------------------
# SIGNAL HANDLER
# ---------------------------------------------------------
handle_signal() {
    local sig=$1
    echo "$(date): Received signal $sig - initiating graceful shutdown..."
    
    SHUTDOWN_REQUESTED=1
    
    # Ensure miner is stopped
    echo "$(date): Stopping miner if running..."
    stop_miner
    
    # Kill any events processes
    pkill -f "docker events" 2>/dev/null || true
    
    exit 0
}

# Setup signal handlers
trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'handle_signal HUP' HUP

# ---------------------------------------------------------
# CONFIGURATION LOADING
# ---------------------------------------------------------
echo "$(date): Starting Docker Events Universal Monitor..."

# -------------------------------------------------
# 1. Load rig config - OC_FILE MUST be set by service
# -------------------------------------------------
if [[ -z "${OC_FILE:-}" ]]; then
    echo "$(date): ERROR: OC_FILE environment variable not set!"
    echo "$(date): Service file must set OC_FILE (e.g., /home/user/rig-cpu.conf or /home/user/rig-gpu.conf)"
    exit 1
fi

echo "$(date): Loading rig config from: $OC_FILE"

if [[ -f "$OC_FILE" ]]; then
    echo "$(date): Rig config found, loading..."
    CFG_FILE="$OC_FILE"
    export CFG_FILE
    USE_CONFIG_FILE=true
else
    echo "$(date): WARNING: Rig config not found at $OC_FILE, using default settings"
    USE_CONFIG_FILE=false
fi

# -------------------------------------------------
# 2. Load miner config
# -------------------------------------------------
: "${MINER_CONF:=/home/user/miner.conf}"
echo "$(date): Loading miner config from: $MINER_CONF"

if [[ -f "$MINER_CONF" ]]; then
    echo "$(date): Miner config found, loading..."
    source "$MINER_CONF"
    USE_CONFIG_FILE=true
else
    echo "$(date): WARNING: Miner config not found at $MINER_CONF, using default settings"
    USE_CONFIG_FILE=false
fi

# -------------------------------------------------
# 3. Load API config
# -------------------------------------------------
: "${API_CONF:=/home/user/api.conf}"
echo "$(date): Loading API config from: $API_CONF"

if [[ -f "$API_CONF" ]]; then
    echo "$(date): API config found, loading..."
    source "$API_CONF"
    
    # Get API settings for this specific miner
    MINER_UPPER=$(echo "$MINER_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    
    # Look for miner-specific API_PORT
    MINER_API_PORT_VAR="${MINER_UPPER}_API_PORT"
    if [[ -n "${!MINER_API_PORT_VAR:-}" ]]; then
        API_PORT="${!MINER_API_PORT_VAR}"
        echo "$(date): Found specific API_PORT: $MINER_API_PORT_VAR=$API_PORT"
    else
        : "${API_PORT:=0}"
    fi
    
    # Look for miner-specific API_HOST
    MINER_API_HOST_VAR="${MINER_UPPER}_API_HOST"
    if [[ -n "${!MINER_API_HOST_VAR:-}" ]]; then
        API_HOST="${!MINER_API_HOST_VAR}"
        echo "$(date): Found specific API_HOST: $MINER_API_HOST_VAR=$API_HOST"
    else
        : "${API_HOST:=127.0.0.1}"
    fi
else
    echo "$(date): WARNING: API config not found at $API_CONF, using default settings"
    # Defaults are already set above
fi

# -------------------------------------------------
# 4. Load libraries if they exist
# -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

BASE_DIR="/home/user/miners"
readonly BASE_DIR

echo "$(date): SCRIPT_DIR=$SCRIPT_DIR"
echo "$(date): BASE_DIR=$BASE_DIR"

mkdir -p "$BASE_DIR"

# Try to load libraries
for f in \
    "$SCRIPT_DIR/lib/00-get_rig_conf.sh" \
    "$SCRIPT_DIR/lib/01-miner_install.sh" \
    "$SCRIPT_DIR/lib/02-load_configs.sh" \
    "$SCRIPT_DIR/lib/03-cpu_threads.sh" \
    "$SCRIPT_DIR/lib/04-algo_config.sh"
do
    if [[ -f "$f" ]]; then
        echo "$(date): Loading library: $(basename "$f")"
        source "$f"
    elif [ "$USE_CONFIG_FILE" = true ]; then
        # Only error if using config files but libraries are missing
        echo "$(date): ERROR: Required library not found: $f"
        exit 1
    fi
done

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
            echo "$(date): teamredminer API flags added"
            echo "$current_args --api_listen=$api_host:$api_PORT"
            ;;
        "nbminer")
            echo "$current_args --api $api_host:$api_PORT"
            ;;
        *)
            # No API flags for unknown miners
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

# First, replace %WORKER_NAME% in WALLET, PASS, POOL
WALLET="${WALLET//%WORKER_NAME%/$WORKER_NAME}"
PASS="${PASS//%WORKER_NAME%/$WORKER_NAME}"
POOL="${POOL//%WORKER_NAME%/$WORKER_NAME}"

# Then replace all placeholders in ARGS
ARGS="${ARGS//%WORKER_NAME%/$WORKER_NAME}"
ARGS="${ARGS//%WALLET%/$WALLET}"
ARGS="${ARGS//%POOL%/$POOL}"

# Add miner-specific API flags
if [[ "$API_PORT" -gt 0 ]]; then
    ARGS=$(add_api_flags "$MINER_NAME" "$API_HOST" "$API_PORT" "$ARGS")
fi

# Get start command
if command -v get_start_cmd >/dev/null 2>&1; then
    START_CMD=$(get_start_cmd "$MINER_NAME")
fi

# Get screen name
if command -v get_rig_conf >/dev/null 2>&1 && [ "$USE_CONFIG_FILE" = true ]; then
    SCREEN_NAME=$(get_rig_conf "SCREEN_NAME" "0")
fi

# If SCREEN_NAME is empty (""), use miner name
if [[ -z "$SCREEN_NAME" ]]; then
    SCREEN_NAME="$MINER_NAME"
fi

echo "$(date): Final configuration:"
echo "$(date):   MINER_NAME: $MINER_NAME"
echo "$(date):   SCREEN_NAME: $SCREEN_NAME"
echo "$(date):   WORKER_NAME: $WORKER_NAME"
echo "$(date):   API: $API_HOST:$API_PORT"
echo "$(date):   WALLET: $WALLET"
echo "$(date):   POOL: $POOL"
echo "$(date):   ARGS: $ARGS"

# ---------------------------------------------------------
# API HEALTH CHECK FUNCTION
# ---------------------------------------------------------
check_api_health() {
    if [[ "$API_PORT" -eq 0 ]]; then
        return 0  # API not enabled, consider healthy
    fi
    # just return healthy...
    return 0
}

# ---------------------------------------------------------
# PID-BASED KILL - Backup for crashed miners
# ---------------------------------------------------------
kill_by_pid() {
    local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
    
    if [[ -f "$pid_file" ]]; then
        local miner_pid=$(cat "$pid_file")
        
        if ps -p "$miner_pid" > /dev/null 2>&1; then
            echo "$(date): WARNING: Miner process still alive after screen quit - forcing kill (PID: $miner_pid)..."
            
            # Send SIGTERM first (graceful)
            kill -15 "$miner_pid" 2>/dev/null
            sleep 2
            
            # Force kill if still running
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "$(date): Miner not responding to SIGTERM - sending SIGKILL..."
                kill -9 "$miner_pid" 2>/dev/null
                sleep 1
            fi
            
            # Kill any child processes
            pkill -P "$miner_pid" 2>/dev/null 2>&1 || true
            
            echo "$(date): Miner process $miner_pid terminated (forcefully)"
        fi
        
        # Clean up PID file
        rm -f "$pid_file"
    fi
}

# ---------------------------------------------------------
# COMMON CHECK FUNCTIONS
# ---------------------------------------------------------
is_docker_running() {
    docker ps > /dev/null 2>&1
    return $?
}

# ---------------------------------------------------------
# DOCKER-SPECIFIC FUNCTIONS
# ---------------------------------------------------------
check_docker_target_container() {
    # Get all containers based on image
    candidates=$(docker ps -a \
        --filter "ancestor=${TARGET_IMAGE}" \
        --format "{{.ID}} {{.Names}}")

    match_id=""

    while read -r cid cname; do
        # Exact match
        if [[ "$cname" == "$TARGET_NAME" ]]; then
            match_id="$cid"
            break
        fi

        # Prefix match: name begins with TARGET_NAME
        if [[ "$cname" == ${TARGET_NAME}* ]]; then
            suffix="${cname#${TARGET_NAME}}"

            # Suffix must be 1+ digits ONLY
            if [[ "$suffix" =~ ^[0-9]+$ ]]; then
                match_id="$cid"
                break
            fi
        fi
    done <<< "$candidates"

    # No matching container found
    if [ -z "$match_id" ]; then
        echo "no matching container found"
        return 1
    fi

    # Check container status
    status=$(docker inspect -f '{{.State.Status}}' "$match_id" 2>/dev/null)

    if [ "$status" = "running" ]; then
        echo "target container running"
        return 0
    else
        echo "target container exists but status=$status"
        return 1
    fi
}

confirm_docker_container_running() {
    local loops=${1:-$DOCKER_RUNNING_CONFIRM_LOOPS}
    local check_interval=2  # seconds
    
    echo "$(date): Confirming Docker target container is running (checking $loops times, $check_interval second intervals)..."
    
    for ((i=1; i<=loops; i++)); do
        echo "$(date): Docker running check $i/$loops..."
        
        # Check if shutdown was requested
        if [[ $SHUTDOWN_REQUESTED -eq 1 ]]; then
            echo "$(date): Shutdown requested during running confirmation, aborting..."
            return 1
        fi
        
        # Check if Docker is running
        if ! is_docker_running; then
            echo "$(date): Docker not running → UNAVAILABLE → BREAKING (cannot confirm)"
            return 1
        fi
        
        # Check if target container exists and is running
        if check_docker_target_container; then
            echo "$(date): Target container confirmed running → continue checking"
            # Continue checking to confirm it's stable
        else
            echo "$(date): Target container NOT running → BREAKING (container not running)"
            return 1
        fi
        
        # If this is not the last check, wait and continue
        if [ $i -lt $loops ]; then
            echo "$(date): Waiting $check_interval seconds for next running check..."
            sleep $check_interval
        fi
    done
    
    echo "$(date): Docker container confirmed running after $loops consecutive checks"
    return 0
}

process_docker_event() {
    local container_name="$1"
    local status="$2"
    local image="$3"
    
    echo "$(date): Docker event - Container: $container_name, Action: $status, Image: $image"
    
    # DOCKER-SPECIFIC LOGIC: Name matching with image
    name_match=0
    if [[ "$container_name" == "$TARGET_NAME" ]]; then
        name_match=1
    elif [[ "$container_name" == ${TARGET_NAME}* ]]; then
        suffix="${container_name#${TARGET_NAME}}"
        if [[ "$suffix" =~ ^[0-9]+$ ]]; then
            name_match=1
        fi
    fi
    
    # Process only if image AND name match
    if [[ "$image" != "$TARGET_IMAGE" ]] || [[ "$name_match" -eq 0 ]]; then
        echo "$(date): Skipping non-matching container"
        return
    fi
    
    # DOCKER LOGIC: 
    # - Start events → CONFIRM container running, then start miner
    # - Stop events → IMMEDIATE stop miner
    case "$status" in
        start|create|unpause|restart)
            echo "$(date): Docker START event ($status) → Confirm container is running, then start miner..."
            
            # Wait a moment for container to fully start
            sleep 1
            
            # Confirm container is actually running (not just transient)
            if confirm_docker_container_running $DOCKER_RUNNING_CONFIRM_LOOPS; then
                echo "$(date): Docker container confirmed running → START miner"
                start_miner
            else
                echo "$(date): Docker container not running (transient state) → no action"
            fi
            ;;
        
        kill|destroy|stop|die|died|pause)
            echo "$(date): Docker STOP/PAUSE event ($status) → IMMEDIATE stop_miner"
            stop_miner
            ;;
        
        *)
            # Ignore irrelevant Docker events
            echo "$(date): DEBUG: Unhandled Docker action: $status for $container_name"
            ;;
    esac
}

# ---------------------------------------------------------
# MINER CONTROL FUNCTIONS
# ---------------------------------------------------------

# Function to start miner
start_miner() {
    # Check if miner is already running
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Screen session exists for $SCREEN_NAME - checking if miner is alive..."
        
        local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
        if [[ -f "$pid_file" ]]; then
            local miner_pid=$(cat "$pid_file")
            
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "$(date): Miner already running in screen session: $SCREEN_NAME"
                echo "$(date): To view: sudo screen -r $SCREEN_NAME"
                return 0  # Exit early - miner is already running
            else
                echo "$(date): Miner process is dead but screen session exists - cleaning up..."
                stop_miner
                echo "$(date): Starting fresh miner after cleanup..."
                # Continue to start fresh miner
            fi
        else
            echo "$(date): Screen session exists but no PID file found - cleaning up..."
            stop_miner
            echo "$(date): Starting fresh miner after cleanup..."
            # Continue to start fresh miner
        fi
    fi
    
    # Start fresh miner
    
    # Apply GPU OC's if configured
    if [[ "${APPLY_OC,,}" == "true" ]]; then
        echo "$(date): Applying GPU clocks..."
        /usr/local/bin/gpu_apply_ocs.sh
    fi
    
    echo "$(date): Starting $SCREEN_NAME..."
    echo "$(date): API: $API_HOST:$API_PORT"
    echo "$(date): Command: $START_CMD $ARGS"
    
    # Create PID file directory
    mkdir -p /tmp/miner_pids
    
    # Start in screen session
    screen -dmS "$SCREEN_NAME" bash -c \
        'echo "Miner starting at $(date)"; \
         echo "API: '"$API_HOST:$API_PORT"'"; \
         echo "$$" > "'"/tmp/${SCREEN_NAME}_miner.pid"'"; \
         trap '\''echo "Miner exiting at $(date)"; rm -f "'"/tmp/${SCREEN_NAME}_miner.pid"'"'\'' EXIT; \
         '"$START_CMD $ARGS"
    
    # Wait a moment for PID file creation
    sleep 2
    
    # Verify startup
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Miner started in screen session: $SCREEN_NAME"
        
        if [[ -f "/tmp/${SCREEN_NAME}_miner.pid" ]]; then
            local miner_pid=$(cat "/tmp/${SCREEN_NAME}_miner.pid")
            echo "$(date): Miner process PID: $miner_pid"
        fi
        
        # Wait for API to come up if enabled
        if [[ "$API_PORT" -gt 0 ]]; then
            echo "$(date): Waiting for API to start (max 30 seconds)..."
            local max_wait=30
            local waited=0
            
            while [[ $waited -lt $max_wait ]]; do
                if check_api_health; then
                    echo "$(date): API is up and running"
                    break
                fi
                sleep 1
                ((waited++))
            done
            
            if [[ $waited -ge $max_wait ]]; then
                echo "$(date): WARNING: API did not respond after $max_wait seconds"
            fi
        fi
        
        echo "$(date): ARGS: $ARGS"
        echo "$(date): To view miner output: sudo screen -r $SCREEN_NAME"
        return 0
    else
        echo "$(date): ERROR: Failed to start screen session!"
        return 1
    fi
}

# Function to stop miner (clean closure first)
stop_miner() {
    echo "$(date): Stopping $SCREEN_NAME miner..."
    
    # Check if screen session exists at all
    if ! screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): No $SCREEN_NAME screen session found - nothing to stop."
        return 0
    fi
    
    # 1. FIRST ATTEMPT: Clean screen quit (let miner cleanup)
    echo "$(date): Sending clean quit to screen session..."
    screen -S "$SCREEN_NAME" -X quit
    
    echo "$(date): Waiting 5 seconds for miner cleanup..."
    sleep 5
    
    # 2. CHECK: If miner process still exists after clean quit
    local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
    if [[ -f "$pid_file" ]]; then
        local miner_pid=$(cat "$pid_file")
        
        if ps -p "$miner_pid" > /dev/null 2>&1; then
            echo "$(date): Miner still running after screen quit - using force cleanup..."
            kill_by_pid
        else
            echo "$(date): Miner exited cleanly after screen quit."
            rm -f "$pid_file"
        fi
    fi
    
    # 3. CLEANUP: Any leftover screen processes
    local screen_pids=$(pgrep -f "SCREEN.*$SCREEN_NAME" 2>/dev/null || true)
    if [[ -n "$screen_pids" ]]; then
        echo "$(date): Cleaning up leftover screen processes..."
        kill -15 $screen_pids 2>/dev/null
        sleep 2
        kill -9 $screen_pids 2>/dev/null 2>&1 || true
    fi
    
    # 4. Reset GPU if configured
    if [[ "${RESET_OC,,}" == "true" ]]; then
        echo "$(date): Resetting GPU clocks and power limits..."
        /usr/local/bin/gpu_reset_poststop.sh
    fi
    
    # 5. Final verification
    echo "$(date): Verifying cleanup..."
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): WARNING: Screen session still exists!"
        return 1
    else
        echo "$(date): Screen session cleaned up successfully."
    fi
    
    # Clean PID file if still exists
    rm -f "$pid_file"
    
    echo "$(date): Final sleep 2 seconds..."
    sleep 2
}

###############################################
#  INITIAL CHECK
###############################################

echo "$(date): Performing initial check..."

# Check if target container is running
if check_docker_target_container; then
    echo "$(date): Docker target container confirmed running at startup → start_miner"
    start_miner
else
    echo "$(date): Docker target container not running at startup → stop_miner"
    stop_miner
fi

###############################################
#  EVENT MONITORING LOOP
###############################################

echo "$(date): Starting Docker event monitor..."

# Main monitoring loop with restart on failure
while [[ $SHUTDOWN_REQUESTED -eq 0 ]]; do
    echo "$(date): Connecting to Docker events stream..."
    
    docker events --format "{{.Type}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}" 2>&1 | \
    while read -r type action name image; do
        # Check for shutdown request
        if [[ $SHUTDOWN_REQUESTED -eq 1 ]]; then
            echo "$(date): Shutdown requested, breaking event loop..."
            break 2  # Break out of both loops
        fi
        
        # Skip non-container events
        if [ "$type" != "container" ]; then
            continue
        fi
        
        # Process Docker event
        process_docker_event "$name" "$action" "$image"
    done
    
    # Events stream ended
    
    # Check if shutdown was requested
    if [[ $SHUTDOWN_REQUESTED -eq 1 ]]; then
        echo "$(date): Shutdown requested, exiting main loop..."
        break
    fi
    
    # Check if docker is running
    if ! is_docker_running; then
        echo "$(date): ERROR: Docker daemon not responding. Waiting 30 seconds..."
        sleep 30
        continue
    fi
    
    # Wait before retrying
    echo "$(date): Docker events stream ended, restarting monitor in 5 seconds..."
    sleep 5
done

# Final cleanup before exit
echo "$(date): Performing final cleanup..."
stop_miner
echo "$(date): Docker event monitor stopped gracefully"
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/docker_events_universal.sh

# -- write GPU service --
sudo tee /etc/systemd/system/docker_events_gpu.service > /dev/null <<'EOF'
[Unit]
Description=Docker Events GPU Miner Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Environment="OC_FILE=/home/user/rig-gpu.conf"
Environment="DOCKER_RUNNING_CONFIRM_LOOPS=2"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
Restart=always
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal

# Allow up to 10 seconds for graceful shutdown
TimeoutStopSec=10
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

# -- write CPU service --
sudo tee /etc/systemd/system/docker_events_cpu.service > /dev/null <<'EOF'
[Unit]
Description=Docker Events CPU Miner Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Environment="OC_FILE=/home/user/rig-cpu.conf"
Environment="DOCKER_RUNNING_CONFIRM_LOOPS=2"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
Restart=always
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal

# Allow up to 10 seconds for graceful shutdown
TimeoutStopSec=10
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker_events_cpu.service
sudo systemctl restart docker_events_gpu.service
sudo systemctl enable docker_events_cpu.service
sudo systemctl enable docker_events_gpu.service

# follow logs
sudo journalctl -u docker_events_cpu.service -f
sudo journalctl -u docker_events_gpu.service -f