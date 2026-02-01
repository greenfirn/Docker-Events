# -- download and extract the miner --

if [ ! -f "/home/user/miners/xmrig/current/xmrig" ]; then
    sudo mkdir -p /home/user/miners/xmrig/current
    cd /home/user/miners/xmrig
    
    sudo wget https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz
    sudo tar -xvf xmrig-6.25.0-linux-static-x64.tar.gz --strip-components=1
    sudo cp -v xmrig /home/user/miners/xmrig/current
else
    echo "xmrig already exists in current directory"
fi

# -- write monitor script --

sudo tee /usr/local/bin/complete_monitor.sh > /dev/null <<'EOF'
#!/bin/bash
# Nosana Monitor - Systemd Journal Compatible Version

# =============== AUTO CPU THREADS AND AFFINITY ===============

MINER_NAME="xmrig"
ALGO="rx/0"

TOTAL_THREADS=$(nproc)
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

# =============== MINER CONFIG ===============

APPLY_OC="false"
RESET_OC="false"

MINER_START_CMD="/home/user/miners/xmrig/current/xmrig"

# WORKER_NAME as hostname capital x,t,s
WORKER_NAME="$(cat /etc/hostname)"
WORKER_NAME="${WORKER_NAME//x/X}"
WORKER_NAME="${WORKER_NAME//t/T}"
WORKER_NAME="${WORKER_NAME//s/S}"

WALLET_ADDRESS="wallet-address"

POOL="pool.supportxmr.com:9000"

CPU_ARGS="-a rx/0 -k -t $AUTOFILL_CPU --randomx-1gb-pages --huge-pages"

API_ARGS="--http-host=127.0.0.1 --http-port=18080"

MINER_ARGS="$CPU_ARGS -p $WORKER_NAME -u $WALLET_ADDRESS --tls -o $POOL $API_ARGS"

MINER_SCREEN_NAME="cpu"

MINER_PID_FILE="/tmp/cpu_miner.pid"

# =============== GLOBAL STATE ===============
CHILD_CONTAINERS=""
SYSTEM_IDLE=true
CONFIRMED_IDLE=false
JOB_COUNT=0
LAST_JOB_START=""
ACTUAL_JOB_START_TIME_FROM_EVENTS=""
LAST_NOSANA_NODE_STATUS=""
LAST_PODMAN_STATUS=""
ALL_PIDS=""
IDLE_CONFIRMATION_COUNT=0
IDLE_CONFIRMATION_THRESHOLD=10
MINING_ENABLED=true
MINING_STARTED=false
LAST_ACTIVE_TIME=0
DOCKER_READY=false
PODMAN_READY=false

# =============== LOGGING FUNCTIONS ===============
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    # Format for systemd journal
    echo "[$timestamp] $level $message"
}

log_info() {
    log "INFO" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_error() {
    log "ERROR" "$1"
}

log_status() {
    local message="$1"
    local timestamp=$(date '+%H:%M:%S')
    
    # Status messages go to stdout without prefix for clean viewing
    echo "[$timestamp] $message"
}

# =============== CLEANUP ===============
cleanup() {
    log_info "🛑 Stopping monitor..."
    
    # Stop miner using PID-based method
    if [ "$MINING_STARTED" = true ]; then
        stop_miner_pid
    fi
    
    for pid in $ALL_PIDS; do
        kill $pid 2>/dev/null && log_info "Killed PID: $pid"
    done
    sleep 1
    for pid in $ALL_PIDS; do
        kill -9 $pid 2>/dev/null && log_info "Force killed PID: $pid"
    done
    log_info "✅ Monitor stopped"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# =============== PID-BASED MINER CONTROL ===============
kill_miner_by_pid() {
    local pid_file="$1"
    local miner_pid
    
    if [[ -f "$pid_file" ]]; then
        miner_pid=$(cat "$pid_file")
        
        if ps -p "$miner_pid" > /dev/null 2>&1; then
            log_warn "Miner process still alive after screen quit - forcing kill (PID: $miner_pid)..."
            
            # Send SIGTERM first (graceful)
            kill -15 "$miner_pid" 2>/dev/null
            sleep 2
            
            # Force kill if still running
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                log_warn "Miner not responding to SIGTERM - sending SIGKILL..."
                kill -9 "$miner_pid" 2>/dev/null
                sleep 1
            fi
            
            # Kill any child processes
            pkill -P "$miner_pid" 2>/dev/null 2>&1 || true
            
            log_info "Miner process $miner_pid terminated (forcefully)"
        fi
        
        # Clean up PID file
        rm -f "$pid_file"
    fi
}

start_miner_pid() {
    local miner_pid
    
    # Check if miner is already running
    if screen -list | grep -q "$MINER_SCREEN_NAME"; then
        log_info "Screen session exists for $MINER_SCREEN_NAME - checking if miner is alive..."
        
        if [[ -f "$MINER_PID_FILE" ]]; then
            miner_pid=$(cat "$MINER_PID_FILE")
            
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                log_info "Miner already running in screen session: $MINER_SCREEN_NAME"
                log_info "To view: sudo screen -r $MINER_SCREEN_NAME"
                MINING_STARTED=true
                return 0
            else
                log_info "Miner process is dead but screen session exists - cleaning up..."
                stop_miner_pid
                log_info "Starting fresh miner after cleanup..."
            fi
        else
            log_info "Screen session exists but no PID file found - cleaning up..."
            stop_miner_pid
            log_info "Starting fresh miner after cleanup..."
        fi
    fi
    
    # Start fresh miner
    log_info "⛏️  Starting miner in screen session..."
    
    # Apply GPU OC's if configured
    if [[ "${APPLY_OC,,}" == "true" ]]; then
        log_info "Applying GPU clocks..."
        /usr/local/bin/gpu_apply_ocs.sh 2>/dev/null || log_warn "Could not apply GPU OC"
    fi
    
    log_info "Command: $MINER_START_CMD $MINER_ARGS"
    
    # Create PID file directory
    mkdir -p $(dirname "$MINER_PID_FILE")
    
    # Start in screen session with PID tracking
    screen -dmS "$MINER_SCREEN_NAME" bash -c \
        'echo "Miner starting at $(date)"; \
         echo "$$" > "'"$MINER_PID_FILE"'"; \
         trap '\''echo "Miner exiting at $(date)"; rm -f "'"$MINER_PID_FILE"'"'\'' EXIT; \
         '"$MINER_START_CMD $MINER_ARGS"
    
    # Wait a moment for PID file creation
    sleep 2
    
    # Verify startup
    if screen -list | grep -q "$MINER_SCREEN_NAME"; then
        log_info "Miner started in screen session: $MINER_SCREEN_NAME"
        
        if [[ -f "$MINER_PID_FILE" ]]; then
            miner_pid=$(cat "$MINER_PID_FILE")
            log_info "Miner process PID: $miner_pid"
        fi
        
        log_info "To view miner output: sudo screen -r $MINER_SCREEN_NAME"
        MINING_STARTED=true
        return 0
    else
        log_error "Failed to start screen session!"
        MINING_STARTED=false
        return 1
    fi
}

stop_miner_pid() {
    local miner_pid
    local screen_pids
    
    log_info "⛏️  Stopping $MINER_SCREEN_NAME miner..."
    
    # Check if screen session exists at all
    if ! screen -list | grep -q "$MINER_SCREEN_NAME"; then
        log_info "No $MINER_SCREEN_NAME screen session found - nothing to stop."
        MINING_STARTED=false
        return 0
    fi
    
    # 1. FIRST ATTEMPT: Clean screen quit (let miner cleanup)
    log_info "Sending clean quit to screen session..."
    screen -S "$MINER_SCREEN_NAME" -X quit
    
    log_info "Waiting 5 seconds for miner cleanup..."
    sleep 5
    
    # 2. CHECK: If miner process still exists after clean quit
    if [[ -f "$MINER_PID_FILE" ]]; then
        miner_pid=$(cat "$MINER_PID_FILE")
        
        if ps -p "$miner_pid" > /dev/null 2>&1; then
            log_info "Miner still running after screen quit - using force cleanup..."
            kill_miner_by_pid "$MINER_PID_FILE"
        else
            log_info "Miner exited cleanly after screen quit."
            rm -f "$MINER_PID_FILE"
        fi
    fi
    
    # 3. CLEANUP: Any leftover screen processes
    screen_pids=$(pgrep -f "SCREEN.*$MINER_SCREEN_NAME" 2>/dev/null || true)
    if [[ -n "$screen_pids" ]]; then
        log_info "Cleaning up leftover screen processes..."
        kill -15 $screen_pids 2>/dev/null
        sleep 2
        kill -9 $screen_pids 2>/dev/null 2>&1 || true
    fi
    
    # 4. Reset GPU if configured
    if [[ "${RESET_OC,,}" == "true" ]]; then
        log_info "Resetting GPU clocks and power limits..."
        /usr/local/bin/gpu_reset_poststop.sh 2>/dev/null || log_warn "Could not reset GPU OC"
    fi
    
    # 5. Final verification
    log_info "Verifying cleanup..."
    if screen -list | grep -q "$MINER_SCREEN_NAME"; then
        log_warn "Screen session still exists!"
        MINING_STARTED=false
        return 1
    else
        log_info "Screen session cleaned up successfully."
    fi
    
    # Clean PID file if still exists
    rm -f "$MINER_PID_FILE"
    
    log_info "Final sleep 2 seconds..."
    sleep 2
    MINING_STARTED=false
}

# =============== DOCKER/PODMAN WAIT FUNCTIONS ===============
wait_for_docker() {
    local wait_count=0
    local max_wait=60
    
    log_info "⏳ Waiting for Docker daemon..."
    
    while [ $wait_count -lt $max_wait ]; do
        if docker version >/dev/null 2>&1; then
            DOCKER_READY=true
            log_info "✅ Docker daemon ready"
            return 0
        fi
        
        wait_count=$((wait_count + 1))
        if [ $((wait_count % 10)) -eq 0 ]; then
            log_info "⏳ Still waiting for Docker daemon... ($wait_count/$max_wait)"
        fi
        sleep 1
    done
    
    log_error "Docker daemon not available after $max_wait seconds"
    return 1
}

wait_for_podman_container() {
    local wait_count=0
    local max_wait=60
    
    log_info "⏳ Waiting for Podman container..."
    
    while [ $wait_count -lt $max_wait ]; do
        if docker ps --filter "name=^podman$" --format "{{.Names}}" | grep -q "^podman$"; then
            sleep 3
            if docker exec podman podman version >/dev/null 2>&1; then
                PODMAN_READY=true
                log_info "✅ Podman container ready"
                return 0
            fi
        fi
        
        wait_count=$((wait_count + 1))
        if [ $((wait_count % 10)) -eq 0 ]; then
            log_info "⏳ Still waiting for Podman container... ($wait_count/$max_wait)"
        fi
        sleep 2
    done
    
    log_warn "Podman container not ready (may start later)"
    return 0
}

is_docker_running() {
    docker version >/dev/null 2>&1 && return 0 || return 1
}

is_podman_container_running() {
    docker ps --filter "name=^podman$" --format "{{.Names}}" | grep -q "^podman$" && return 0 || return 1
}

# =============== HELPER FUNCTIONS ===============
get_container_status() {
    local container_name=$1
    docker ps --filter "name=^${container_name}$" --format "{{.Status}}" 2>/dev/null || echo "NOT_RUNNING"
}

get_child_containers() {
    if [ "$PODMAN_READY" = true ] && is_podman_container_running; then
        docker exec podman podman ps --format "{{.Names}}" 2>/dev/null | \
            grep -v "^tunnel-api-" | \
            grep -v "^frpc-api-" | \
            sort | tr '\n' ' ' | xargs
    else
        echo ""
    fi
}

format_duration() {
    local seconds=$1
    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        local minutes=$((seconds / 60))
        local remaining=$((seconds % 60))
        echo "${minutes}m${remaining}s"
    else
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        local remaining=$((seconds % 60))
        echo "${hours}h${minutes}m${remaining}s"
    fi
}

calculate_duration() {
    local start_time=$1
    local end_time=$2
    local start_seconds
    local end_seconds
    local duration
    
    start_seconds=$(date -d "$start_time" +%s 2>/dev/null || echo "$start_time")
    end_seconds=$(date -d "$end_time" +%s 2>/dev/null || echo "$end_time")
    duration=$((end_seconds - start_seconds))
    format_duration $duration
}

is_system_active_now() {
    local children
    
    # Check Docker first
    if ! is_docker_running; then
        DOCKER_READY=false
        PODMAN_READY=false
        echo "active:no-docker"  # Docker not running = ACTIVE (don't mine)
        return 0
    fi
    
    DOCKER_READY=true
    
    # Check if Podman container is running
    if ! is_podman_container_running; then
        PODMAN_READY=false
        echo "active:no-podman"  # Podman not running = ACTIVE (don't mine)
        return 0
    fi
    
    PODMAN_READY=true
    
    # Get child containers from Podman
    children=$(get_child_containers)
    
    if [ -n "$children" ]; then
        echo "active:children:$children"  # Has child containers = ACTIVE
        return 0
    else
        echo "idle"  # Podman running but no child containers = IDLE (can mine)
        return 1
    fi
}

# Main state update function
# Accepts: 0 = stop-like event, 1 = start-like event
# Returns: 0 if state changed, 1 if already in target state
update_system_state() {
    local event_type="$1"  # 0 = stop, 1 = start
    local state
    local reason
    local children
    local duration
    
    # If no event type specified, check current state
    if [ -z "$event_type" ]; then
        state=$(is_system_active_now)
    else
        # Use event type to determine target state
        if [ "$event_type" -eq 1 ]; then
            # Start-like event: target is ACTIVE state
            if [ "$SYSTEM_IDLE" = false ] && [ "$CONFIRMED_IDLE" = false ]; then
                # Already in ACTIVE state, skip
                return 1
            fi
            state="active:event"
        else
            # Stop-like event: target is IDLE state
            # Skip if we've already triggered first idle (IDLE_CONFIRMATION_COUNT >= 1)
            # This prevents multiple stop events from resetting the confirmation process
            if [ "$IDLE_CONFIRMATION_COUNT" -ge 1 ]; then
                # Already in idle confirmation process, skip additional stop events
                return 1
            fi
            state="idle"
        fi
    fi
    
    if [[ "$state" == active:* ]]; then
        # SYSTEM IS ACTIVE (for any reason: no-docker, no-podman, or has children)
        IFS=':' read -r _ reason children <<< "$state"
        
        LAST_ACTIVE_TIME=$(date +%s)
        IDLE_CONFIRMATION_COUNT=0
        
        if [ "$SYSTEM_IDLE" = true ] || [ "$CONFIRMED_IDLE" = true ]; then
            SYSTEM_IDLE=false
            CONFIRMED_IDLE=false
            JOB_COUNT=$((JOB_COUNT + 1))
            
            # Use actual event time if available, otherwise use detection time
            if [ -n "$ACTUAL_JOB_START_TIME_FROM_EVENTS" ]; then
                LAST_JOB_START="$ACTUAL_JOB_START_TIME_FROM_EVENTS"
            else
                LAST_JOB_START=$(date '+%H:%M:%S')
            fi
            
            # Stop mining when system becomes active (using PID method)
            stop_miner_pid
            
            log_info "🚨 SYSTEM_ACTIVE #$JOB_COUNT"
            log_info "  Reason: $reason"
            log_info "  Time: $LAST_JOB_START"
            [ "$reason" = "children" ] && [ -n "$children" ] && log_info "  Podman children: $children"
        fi
        
        # Update global state
        CHILD_CONTAINERS="$children"
        return 0
        
    else
        # SYSTEM IS IDLE (Podman running with no child containers)
        if [ "$SYSTEM_IDLE" = false ]; then
            # Just transitioned from active to idle
            SYSTEM_IDLE=true
            CONFIRMED_IDLE=false
            IDLE_CONFIRMATION_COUNT=1
            
            log_info "⏳ Idle detected, confirming... (1/$IDLE_CONFIRMATION_THRESHOLD)"
            
        elif [ "$CONFIRMED_IDLE" = false ]; then
            # Already in potentially idle state, increment confirmation
            IDLE_CONFIRMATION_COUNT=$((IDLE_CONFIRMATION_COUNT + 1))
            
            if [ "$IDLE_CONFIRMATION_COUNT" -ge "$IDLE_CONFIRMATION_THRESHOLD" ]; then
                # Confirmed idle!
                CONFIRMED_IDLE=true
                
                # Start mining when confirmed idle (using PID method)
                start_miner_pid
                
                log_info "✅ Confirmed IDLE - Starting mining"
                
                # Log job duration if we just finished one
                if [ -n "$LAST_JOB_START" ]; then
                    duration=$(calculate_duration "$LAST_JOB_START" "$(date '+%H:%M:%S')")
                    log_info "⏱️  Job #$JOB_COUNT: $duration"
                    LAST_JOB_START=""
                    ACTUAL_JOB_START_TIME_FROM_EVENTS=""
                fi
            else
                log_info "⏳ Confirming idle... ($IDLE_CONFIRMATION_COUNT/$IDLE_CONFIRMATION_THRESHOLD)"
            fi
        fi
        
        # Update global state (empty)
        CHILD_CONTAINERS=""
        return 0
    fi
}

update_status_display() {
    local NOSANA_STATUS="?"
    local PODMAN_STATUS="?"
    local NOSANA_ICON="🟢"
    local PODMAN_ICON="🟢"
    local INDICATORS=""
    local CHILD_COUNT=0
    local MINING_ICON=""
    local STATE_REASON=""
    
    # Get container status
    if [ "$DOCKER_READY" = true ]; then
        NOSANA_STATUS=$(get_container_status "nosana-node")
        PODMAN_STATUS=$(get_container_status "podman")
    fi
    
    [ "$NOSANA_STATUS" = "NOT_RUNNING" ] && NOSANA_ICON="🔴"
    echo "$NOSANA_STATUS" | grep -q "(healthy)" && NOSANA_ICON="✅"
    echo "$NOSANA_STATUS" | grep -q "(unhealthy)" && NOSANA_ICON="⚠️"
    
    [ "$PODMAN_STATUS" = "NOT_RUNNING" ] && PODMAN_ICON="🔴"
    echo "$PODMAN_STATUS" | grep -q "(healthy)" && PODMAN_ICON="✅"
    echo "$PODMAN_STATUS" | grep -q "(unhealthy)" && PODMAN_ICON="⚠️"
    
    if [ "$DOCKER_READY" = false ]; then
        NOSANA_ICON="🔵"
        PODMAN_ICON="🔵"
        STATE_REASON="(no-docker)"
    elif [ "$PODMAN_READY" = false ]; then
        STATE_REASON="(no-podman)"
    fi
    
    if [ "$CONFIRMED_IDLE" = true ]; then
        [ "$MINING_STARTED" = true ] && MINING_ICON="⛏️🔥"
        [ "$MINING_ENABLED" = false ] && MINING_ICON=""
        
        log_status "✅ IDLE $MINING_ICON | Jobs: $JOB_COUNT | Node:$NOSANA_ICON Podman:$PODMAN_ICON"
    elif [ "$SYSTEM_IDLE" = true ]; then
        log_status "⏳ IDLE? ($IDLE_CONFIRMATION_COUNT/$IDLE_CONFIRMATION_THRESHOLD) | Jobs: $JOB_COUNT | Node:$NOSANA_ICON Podman:$PODMAN_ICON"
    else
        CHILD_COUNT=$(echo "$CHILD_CONTAINERS" | wc -w 2>/dev/null || echo 0)
        [ $CHILD_COUNT -gt 0 ] && INDICATORS="📦$CHILD_COUNT"
        [ -n "$STATE_REASON" ] && INDICATORS="$STATE_REASON"
        
        log_status "🔴 ACTIVE $INDICATORS [started: $LAST_JOB_START] | Job #$JOB_COUNT | Node:$NOSANA_ICON Podman:$PODMAN_ICON"
    fi
}

# =============== INITIALIZATION ===============
log_info "========================================"
log_info "NOSANA MONITOR - SYSTEMD JOURNAL VERSION"
log_info "Started: $(date '+%H:%M:%S')"
log_info "Mining: $MINING_ENABLED"
log_info "Miner Screen: $MINER_SCREEN_NAME"
log_info "Idle confirm: ${IDLE_CONFIRMATION_THRESHOLD}×5s"
log_info "========================================"

# =============== WAIT FOR DOCKER AND PODMAN ===============
log_info "🔄 Initializing Docker/Podman..."

# Wait for Docker daemon
wait_for_docker

# Wait for Podman container
wait_for_podman_container

# =============== INITIAL STATE ===============
log_info "🔄 Getting initial state..."

# Get initial status
if [ "$DOCKER_READY" = true ]; then
    LAST_NOSANA_NODE_STATUS=$(get_container_status "nosana-node")
    LAST_PODMAN_STATUS=$(get_container_status "podman")
    
    log_info "Initial status:"
    log_info "  nosana-node: $LAST_NOSANA_NODE_STATUS"
    log_info "  podman: $LAST_PODMAN_STATUS"
fi

# Initial state check
update_system_state

log_info "Initial containers:"
log_info "  Podman children: $CHILD_CONTAINERS"

# =============== PODMAN EVENTS MONITOR ===============
(
    log_info "📡 Starting Podman events monitor..."
    trap 'exit 0' SIGINT SIGTERM
    
    # Function to process Podman events
    process_podman_event() {
        local event_line="$1"
        local event_time
        local status
        local container_name
        local event_type
        local event_hms
        
        [ -z "$event_line" ] && return
        
        # Try to parse the event line
        # Format: "2026-02-01 14:56:32.123456789 +0000 UTC start container_name"
        event_time=$(echo "$event_line" | awk '{print $1" "$2" "$3" "$4" "$5}')
        status=$(echo "$event_line" | awk '{print $6}')
        container_name=$(echo "$event_line" | awk '{print $7}')
        
        # If parsing failed, try alternative
        if [ -z "$container_name" ]; then
            # Maybe format is different
            event_time=$(echo "$event_line" | cut -d' ' -f1-5)
            status=$(echo "$event_line" | cut -d' ' -f6)
            container_name=$(echo "$event_line" | cut -d' ' -f7-)
        fi
        
        [ -z "$container_name" ] && return
        [[ "$container_name" =~ ^(tunnel-api-|frpc-api-) ]] && return
        
        log_info "📦 PODMAN EVENT: $status $container_name (time: $event_time)"
        
        # Determine event type
        event_type=0
        
        if [[ "$status" == "create" || "$status" == "start" || "$status" == "unpause" || "$status" == "restart" ]]; then
            event_type=1
            
            if [[ -z "$ACTUAL_JOB_START_TIME_FROM_EVENTS" ]]; then
                # Extract just HH:MM:SS from timestamp
                event_hms=$(echo "$event_time" | grep -o '[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' || echo "$(date '+%H:%M:%S')")
                ACTUAL_JOB_START_TIME_FROM_EVENTS="$event_hms"
                log_info "📦 ACTUAL JOB START TIME: $ACTUAL_JOB_START_TIME_FROM_EVENTS"
            fi
        elif [[ "$status" == "stop" || "$status" == "die" || "$status" == "pause" || "$status" == "kill" || "$status" == "remove" ]]; then
            event_type=0
        else
            return
        fi
        
        # Update state
        if update_system_state "$event_type"; then
            log_info "📦 Processed $status event"
        else
            log_info "📦 Skipped $status event"
        fi
    }
    
    while true; do
        if ! is_docker_running; then
            log_error "Docker daemon stopped!"
            sleep 5
            continue
        fi
        
        if ! is_podman_container_running; then
            log_error "Podman container stopped!"
            sleep 5
            continue
        fi
        
        if ! docker exec podman podman version >/dev/null 2>&1; then
            log_warn "Podman inside container not responding..."
            sleep 5
            continue
        fi
        
        # Use simpler format that's easier to parse
        docker exec podman podman events \
            --filter 'type=container' \
            --format '{{.Time}} {{.Status}} {{.Name}}' 2>&1 | \
        while IFS= read -r event_line; do
            if ! is_docker_running || ! is_podman_container_running; then
                log_error "Docker/Podman stopped during events!"
                break
            fi
            
            process_podman_event "$event_line"
        done
        
        log_info "🔄 Podman events stream ended, restarting..."
        sleep 2
    done
) &
PODMAN_EVENTS_PID=$!
ALL_PIDS="$ALL_PIDS $PODMAN_EVENTS_PID"

log_info "Monitor PIDs: Podman=$PODMAN_EVENTS_PID"
log_info "miner command..."
log_info "$MINER_START_CMD"
log_info "$MINER_ARGS"
log_info "✅ Monitor started successfully"

# =============== MAIN LOOP ===============
HEARTBEAT=0
while true; do
    HEARTBEAT=$((HEARTBEAT + 1))
    
    # Heartbeat every 30 seconds
    if [ $((HEARTBEAT % 30)) -eq 0 ]; then
        log_info "💓 Monitor running - Jobs: $JOB_COUNT"
    fi
    
    # Update state EVERY 5 seconds (polling - no event type)
    if [ $((HEARTBEAT % 5)) -eq 0 ]; then
        update_system_state  # No event type = check current state
    fi
    
    # Update status display (clean output for journal)
    update_status_display
    
    sleep 1
done
EOF

# Make the monitor script executable
sudo chmod +x /usr/local/bin/complete_monitor.sh

# Create the service file
sudo tee /etc/systemd/system/docker_events_cpu.service > /dev/null <<'EOF'
[Unit]
Description=Nosana Complete Monitor Service
After=docker.service
After=network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/complete_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable docker_events_cpu.service

# Start/Stop Service
sudo systemctl start docker_events_cpu.service
sudo systemctl stop docker_events_cpu.service

# check status
sudo systemctl status docker_events_cpu.service

# follow logs
sudo journalctl -u docker_events_cpu.service -f

# show more logs
sudo journalctl -u docker_events_cpu.service -e

# disable so it doesnt start on boot
sudo systemctl disable docker_events_cpu.service