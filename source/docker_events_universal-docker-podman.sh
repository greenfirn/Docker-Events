sudo tee /usr/local/bin/docker_events_universal.sh > /dev/null <<'EOF'
#!/bin/bash

set -Eeuo pipefail
shopt -s inherit_errexit

# ---------------------------------------------------------
# GLOBAL VARIABLES FOR SIGNAL HANDLING
# ---------------------------------------------------------
SHUTDOWN_REQUESTED=0
PODMAN_READY=false
USE_PODMAN_EVENTS=false

# ---------------------------------------------------------
# CONFIGURABLE SETTINGS
# ---------------------------------------------------------
# Number of times to check for idle state for Podman
: "${PODMAN_IDLE_CONFIRM_LOOPS:=3}"

# Number of times to check for running state for Docker  
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
    if [ "$USE_PODMAN_EVENTS" = true ]; then
        pkill -f "podman events" 2>/dev/null || true
    else
        pkill -f "docker events" 2>/dev/null || true
    fi
    
    exit 0
}

# Setup signal handlers
trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'handle_signal HUP' HUP

# Where miners are installed
BASE_DIR="/home/user/miners"
readonly BASE_DIR

# Where THIS script and lib/ live
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

echo "[init] SCRIPT_DIR=$SCRIPT_DIR"
echo "[init] BASE_DIR=$BASE_DIR"

mkdir -p "$BASE_DIR"

# -------------------------------------------------
# Rig config (must be set by service)
# -------------------------------------------------
: "${OC_FILE:?OC_FILE is not set}"
CFG_FILE="$OC_FILE"
export CFG_FILE

[[ -f "$CFG_FILE" ]] || {
    echo "Missing rig config: $CFG_FILE"
    exit 1
}

# -------------------------------------------------
# Miner config (with default location)
# -------------------------------------------------
: "${MINER_CONF:=/home/user/miner.conf}"
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

# ---------------------------------------------------------
# DETERMINE EVENT SOURCE BASED ON TARGET_NAME (already loaded from config)
# ---------------------------------------------------------
if [ "$TARGET_NAME" = "podman" ]; then
    USE_PODMAN_EVENTS=true
    echo "$(date): TARGET_NAME='podman' detected → Using Podman events"
    echo "$(date): Podman idle confirm loops: $PODMAN_IDLE_CONFIRM_LOOPS"
else
    USE_PODMAN_EVENTS=false
    echo "$(date): TARGET_NAME='${TARGET_NAME}' → Using Docker events"
    echo "$(date): Target Image: ${TARGET_IMAGE}"
    echo "$(date): Docker running confirm loops: $DOCKER_RUNNING_CONFIRM_LOOPS"
fi

# ---------------------------------------------------------
# API SETTINGS - from API_CONF or default location
# ---------------------------------------------------------
# Use API_CONF environment variable if set, otherwise default
: "${API_CONF:=/home/user/api.conf}"
PORTS_CONF="$API_CONF"

if [[ ! -f "$PORTS_CONF" ]]; then
    echo "[api] WARNING: $PORTS_CONF not found, API disabled"
    API_HOST="127.0.0.1"
    API_PORT=0
else
    echo "[api] Loading API settings from $PORTS_CONF"
    # Source ports.conf
    source "$PORTS_CONF"
    
    # Get API settings for this specific miner
    MINER_UPPER=$(echo "$MINER_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    
    # Look for miner-specific API_PORT (e.g., XMRIG_CPU_API_PORT)
    MINER_API_PORT_VAR="${MINER_UPPER}_API_PORT"
    if [[ -n "${!MINER_API_PORT_VAR:-}" ]]; then
        API_PORT="${!MINER_API_PORT_VAR}"
        echo "[api] Found specific API_PORT: $MINER_API_PORT_VAR=$API_PORT"
    else
        # Fallback to generic API_PORT
        : "${API_PORT:=0}"
        echo "[api] Using generic API_PORT: $API_PORT"
    fi
    
    # Look for miner-specific API_HOST (e.g., XMRIG_CPU_API_HOST)
    MINER_API_HOST_VAR="${MINER_UPPER}_API_HOST"
    if [[ -n "${!MINER_API_HOST_VAR:-}" ]]; then
        API_HOST="${!MINER_API_HOST_VAR}"
        echo "[api] Found specific API_HOST: $MINER_API_HOST_VAR=$API_HOST"
    else
        # Fallback to generic API_HOST
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
            echo "$(date): teamredminer API flags added"
            echo "$current_args --api_listen=$api_host:$api_port"
            ;;
        "nbminer")
            echo "$current_args --api $api_host:$api_port"
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

# Replace %WORKER_NAME% placeholder in ARGS, WALLET, PASS, POOL
ARGS="${ARGS//%WORKER_NAME%/$WORKER_NAME}"
WALLET="${WALLET//%WORKER_NAME%/$WORKER_NAME}"
PASS="${PASS//%WORKER_NAME%/$WORKER_NAME}"
POOL="${POOL//%WORKER_NAME%/$WORKER_NAME}"

# Add miner-specific API flags
if [[ "$API_PORT" -gt 0 ]]; then
        ARGS=$(add_api_flags "$MINER_NAME" "$API_HOST" "$API_PORT" "$ARGS")
fi

START_CMD=$(get_start_cmd "$MINER_NAME")

# Load from rig.conf
SCREEN_NAME=$(get_rig_conf "SCREEN_NAME" "0")

# If SCREEN_NAME is empty (""), ignore and use miner name
if [[ -z "$SCREEN_NAME" ]]; then
    SCREEN_NAME="$MINER_NAME"
fi

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
# PODMAN-SPECIFIC FUNCTIONS
# ---------------------------------------------------------
is_podman_container_running() {
    docker ps --filter "name=^podman$" --format "{{.Names}}" | grep -q "^podman$" && return 0 || return 1
}

get_podman_child_containers() {
    if [ "$PODMAN_READY" = true ] && is_podman_container_running; then
        docker exec podman podman ps --format "{{.Names}}" 2>/dev/null | \
            grep -v "^tunnel-api-" | \
            grep -v "^frpc-api-" | \
            sort | tr '\n' ' ' | xargs
    else
        echo ""
    fi
}

confirm_podman_idle() {
    local loops=${1:-$PODMAN_IDLE_CONFIRM_LOOPS}
    local check_interval=5  # seconds
    
    echo "$(date): Confirming Podman is idle (checking $loops times, $check_interval second intervals)..."
    
    for ((i=1; i<=loops; i++)); do
        echo "$(date): Podman idle check $i/$loops..."
        
        # Check if shutdown was requested
        if [[ $SHUTDOWN_REQUESTED -eq 1 ]]; then
            echo "$(date): Shutdown requested during idle confirmation, aborting..."
            return 1
        fi
        
        # Check if Podman container is running
        if ! is_podman_container_running; then
            echo "$(date): Podman container not found → UNAVAILABLE → BREAKING (safe failure mode)"
            return 1
        fi
        
        # Get current child containers
        local child_containers=$(get_podman_child_containers)
        
        if [ -n "$child_containers" ]; then
            echo "$(date): Found child containers: [$child_containers] → BREAKING idle check (Podman busy)"
            return 1
        else
            echo "$(date): No child containers found → Podman IDLE"
        fi
        
        # If this is not the last check, wait and continue
        if [ $i -lt $loops ]; then
            echo "$(date): Waiting $check_interval seconds for next idle check..."
            sleep $check_interval
        fi
    done
    
    echo "$(date): Podman confirmed idle after $loops consecutive checks"
    return 0
}

process_podman_event() {
    local container_name="$1"
    local status="$2"
    local event_time="$3"
    
    # echo "$(date): Podman event - Container: $container_name, Status: $status, Time: $event_time"
    
    # Skip tunnel-api and frpc-api containers
    if [[ "$container_name" == tunnel-api-* ]] || [[ "$container_name" == frpc-api-* ]]; then
        echo "$(date): Skipping tunnel/frpc container: $container_name"
        return
    fi
    
    # PODMAN LOGIC: 
    # - Start events → IMMEDIATE stop miner (Podman busy)
    # - Stop events → Confirm Podman idle, then start miner
    case "$status" in
        init|start|create|unpause|restart)
            echo "$(date): IMMEDIATE REACTION to Podman $status event → Podman busy → INSTANT stop_miner"
            stop_miner
            ;;
        
        kill|destroy|stop|die|died|pause)
            echo "$(date): Podman STOP/PAUSE event ($status) → Confirm Podman idle, then start miner..."
            
            # Wait a moment for operation to complete
            sleep 1
            
            # Confirm Podman is actually idle
            if confirm_podman_idle $PODMAN_IDLE_CONFIRM_LOOPS; then
                echo "$(date): Podman confirmed IDLE → start_miner"
                start_miner
            else
                echo "$(date): Podman still busy or unavailable → keep miner stopped"
            fi
            ;;
        
        *)
            # Ignore irrelevant Podman events
            # echo "$(date): DEBUG: Unhandled Podman status: $status for $container_name"
            ;;
    esac
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
    
    # echo "$(date): Docker event - Container: $container_name, Action: $status, Image: $image"
    
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
            # echo "$(date): DEBUG: Unhandled Docker action: $status for $container_name"
            ;;
    esac
}

# ---------------------------------------------------------
# MINER CONTROL FUNCTIONS (Common to both modes)
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
    echo "$(date): Command: $START_CMD"
    
    # Create PID file directory
    mkdir -p /tmp/miner_pids
    
    # Start in screen session
    screen -dmS "$SCREEN_NAME" bash -c \
        'echo "Miner starting at $(date)"; \
         echo "API: '"$API_HOST:$API_PORT"'"; \
         echo "$$" > "'"/tmp/${SCREEN_NAME}_miner.pid"'"; \
         trap '\''echo "Miner exiting at $(date)"; rm -f "'"/tmp/${SCREEN_NAME}_miner.pid"'"'\'' EXIT; \
         '"$START_CMD"
    
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
        
        echo "$(date): ARGS/OCS: $ARGS"
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
#  INITIAL CHECK (Mode-specific)
###############################################

echo "$(date): Performing initial check..."

if [ "$USE_PODMAN_EVENTS" = true ]; then
    # PODMAN MODE: Wait for Podman container to be ready
    echo "$(date): Waiting for Podman container to be ready..."
    max_wait=60
    waited=0
    while [[ $waited -lt $max_wait ]]; do
        if is_podman_container_running; then
            echo "$(date): Podman container is running"
            PODMAN_READY=true
            break
        fi
        sleep 1
        ((waited++))
    done
    
    if [ "$PODMAN_READY" = true ]; then
        # Initial idle confirmation for Podman
        if confirm_podman_idle $PODMAN_IDLE_CONFIRM_LOOPS; then
            echo "$(date): Podman confirmed IDLE at startup → start_miner"
            start_miner
        else
            echo "$(date): Podman BUSY or UNAVAILABLE at startup → stop_miner"
            stop_miner
        fi
    else
        echo "$(date): Podman container not ready after $max_wait seconds → stop_miner"
        stop_miner
    fi
else
    # DOCKER MODE: Check if target container is running, confirm, then start miner
    echo "$(date): Checking Docker target container..."
    
    if confirm_docker_container_running $DOCKER_RUNNING_CONFIRM_LOOPS; then
        echo "$(date): Docker target container confirmed running at startup → start_miner"
        start_miner
    else
        echo "$(date): Docker target container not running at startup → stop_miner"
        stop_miner
    fi
fi

###############################################
#  EVENT MONITORING LOOP (Mode-specific)
###############################################

echo "$(date): Starting event monitor..."

# Main monitoring loop with restart on failure
while [[ $SHUTDOWN_REQUESTED -eq 0 ]]; do
    if [ "$USE_PODMAN_EVENTS" = true ]; then
        # PODMAN EVENT STREAM
        echo "$(date): Connecting to Podman events stream..."
        
        docker exec podman podman events \
            --filter 'type=container' \
            --format '{{.Time}}|{{.Status}}|{{.Name}}' 2>&1 | \
        while IFS='|' read -r event_time status container_name; do
            # Check for shutdown request
            if [[ $SHUTDOWN_REQUESTED -eq 1 ]]; then
                echo "$(date): Shutdown requested, breaking event loop..."
                break 2  # Break out of both loops
            fi
            
            # Skip empty lines or malformed events
            [ -z "$status" ] && continue
            [ -z "$container_name" ] && continue
            
            # Process Podman event
            process_podman_event "$container_name" "$status" "$event_time"
        done
    else
        # DOCKER EVENT STREAM
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
    fi
    
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
    
    if [ "$USE_PODMAN_EVENTS" = true ]; then
        # Check if podman container is running
        if ! is_podman_container_running; then
            echo "$(date): ERROR: Podman container not running. Waiting 30 seconds..."
            PODMAN_READY=false
            
            # Wait for Podman to restart
            max_wait=60
            waited=0
            while [[ $waited -lt $max_wait && $SHUTDOWN_REQUESTED -eq 0 ]]; do
                if is_podman_container_running; then
                    echo "$(date): Podman container restarted"
                    PODMAN_READY=true
                    break
                fi
                sleep 1
                ((waited++))
            done
            
            if [ "$PODMAN_READY" = false ]; then
                echo "$(date): Podman container not available after $max_wait seconds"
                stop_miner
                continue
            fi
        fi
    fi
    
    # Wait before retrying
    echo "$(date): Events stream ended, restarting monitor in 5 seconds..."
    sleep 5
done

# Final cleanup before exit
echo "$(date): Performing final cleanup..."
stop_miner
echo "$(date): Event monitor stopped gracefully"
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
#Environment="MINER_CONF=/home/user/miner.conf"
#Environment="API_CONF=/home/user/api.conf"
Environment="PODMAN_IDLE_CONFIRM_LOOPS=7"
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
#Environment="MINER_CONF=/home/user/miner.conf"
#Environment="API_CONF=/home/user/api.conf"
Environment="PODMAN_IDLE_CONFIRM_LOOPS=7"
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