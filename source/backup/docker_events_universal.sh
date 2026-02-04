# docker_events_universal.sh

sudo tee /usr/local/bin/docker_events_universal.sh > /dev/null <<'EOF'
#!/bin/bash

set -Eeuo pipefail
shopt -s inherit_errexit

# ---------------------------------------------------------
# GLOBAL VARIABLES FOR SIGNAL HANDLING
# ---------------------------------------------------------
SHUTDOWN_REQUESTED=0

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
    
    # Kill any docker events process
    pkill -f "docker events" 2>/dev/null || true
    
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
# FUNCTIONS
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

check_target_container() {
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
        echo "no matching container treat as stopped"
        return 1
    fi

    # Check container status
    status=$(docker inspect -f '{{.State.Status}}' "$match_id" 2>/dev/null)

    if [ "$status" = "running" ]; then
        return 0
    else
        echo "status=$status treat as stopped"
        return 1
    fi
}

###############################################
#  INITIAL CHECK
###############################################

if check_target_container; then
    echo "$(date): Target container (${TARGET_IMAGE} name ${TARGET_NAME}) detected at startup"
    start_miner
else
    echo "$(date): Target container (${TARGET_IMAGE} name ${TARGET_NAME}) not found at startup"
    stop_miner
fi

###############################################
#  DOCKER EVENT LOOP WITH RETRY AND SIGNAL HANDLING
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
            echo "$(date): non-container event: Type: $type, Action: $action, Name: $name"
            continue
        fi

        echo "$(date): Container event detected - Action: $action, Name: $name, Image: $image"

        #########################################################
        # NAME MATCHING — Exact, or Starts-With + DIGIT SUFFIX
        #########################################################
        name_match=0

        # Exact match
        if [[ "$name" == "$TARGET_NAME" ]]; then
            name_match=1

        # Starts-with, check digit suffix
        elif [[ "$name" == ${TARGET_NAME}* ]]; then
            suffix="${name#${TARGET_NAME}}"
            if [[ "$suffix" =~ ^[0-9]+$ ]]; then
                name_match=1
            fi
        fi

        #########################################################
        # Process only if image AND name match
        #########################################################
        if [[ "$image" == "$TARGET_IMAGE" && "$name_match" -eq 1 ]]; then

        case "$action" in
            start|create|unpause)
                echo "$(date): START event detected → Wait for start to complete"
                retry_count=0
                started=false
                
                while [[ $retry_count -lt 10 && $SHUTDOWN_REQUESTED -eq 0 ]]; do  # Added shutdown check
                    sleep 0.2  # Slightly longer delay for start operations
                    
                    # Check if container exists and is running
                    if docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null | grep -q "running"; then
                        echo "$(date): Container confirmed running → start_miner"
                        start_miner
                        started=true
                        break
                    fi
                    
                    retry_count=$((retry_count + 1))
                    echo "$(date): Start check attempt $retry_count: container not yet running"
                done
                
                # Final check if loop completed without success
                if [[ "$started" = false && $SHUTDOWN_REQUESTED -eq 0 ]]; then
                    echo "$(date): WARNING: Container $name never reached 'running' state after $retry_count attempts"
                    # Optional: Check if container exists at all
                    if ! docker inspect "$name" &>/dev/null; then
                        echo "$(date): Container $name no longer exists"
                    fi
                fi
                ;;

            kill|destroy|stop|die)
                echo "$(date): STOP event detected ($action) → stop_miner"
                # Immediate action for destructive events
                stop_miner
                ;;
                
            pause)
                echo "$(date): PAUSE event detected → Wait for pause to complete"
                retry_count=0
                
                while [[ $retry_count -lt 5 && $SHUTDOWN_REQUESTED -eq 0 ]]; do
                    sleep 0.1
                    status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")
                    
                    case "$status" in
                        "paused")
                            echo "$(date): Container confirmed paused → stop_miner"
                            stop_miner
                            break
                            ;;
                        "not_found")
                            echo "$(date): Container removed while pausing → stop_miner"
                            stop_miner
                            break
                            ;;
                        "exited"|"dead")
                            echo "$(date): Container exited/died instead of pausing → stop_miner"
                            stop_miner
                            break
                            ;;
                    esac
                    
                    retry_count=$((retry_count + 1))
                done
                
                # Final check after loop
                if [[ $retry_count -eq 5 && $SHUTDOWN_REQUESTED -eq 0 ]]; then
                    echo "$(date): WARNING: Container $name never reached 'paused' state, checking current status"
                    final_status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")
                    if [[ "$final_status" != "running" ]]; then
                        echo "$(date): Container is $final_status → stop_miner"
                        stop_miner
                    fi
                fi
                ;;
                
            *)
                # Ignore irrelevant Docker events
                echo "$(date): DEBUG: Unhandled action: $action for $name"
                ;;
        esac
        fi
    done
    
    # Docker events stream ended
    
    # Check if shutdown was requested
    if [[ $SHUTDOWN_REQUESTED -eq 1 ]]; then
        echo "$(date): Shutdown requested, exiting main loop..."
        break
    fi
    
    # Check if docker is running
    if ! docker ps > /dev/null 2>&1; then
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
#Environment="MINER_CONF=/home/user/miner.conf"
#Environment="API_CONF=/home/user/api.conf"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
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
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
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