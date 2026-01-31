# stop old services
sudo systemctl stop docker_events_gpu.service
sudo systemctl stop docker_events_cpu.service

# disable so it doesnt run on boot
sudo systemctl disable docker_events_gpu.service
sudo systemctl disable docker_events_cpu.service


# -- write docker_events_cpu script --
sudo mkdir -v /usr/local/bin

sudo tee /usr/local/bin/docker_events_cpu.sh > /dev/null <<'EOF'
#!/bin/bash

set -euo pipefail

#======= Miner Start Settings ================================================

# remove xmrig to update
# sudo rm -rv /home/user/miners/xmrig

if [ ! -f "/home/user/miners/xmrig/current/xmrig" ]; then
    sudo mkdir -p /home/user/miners/xmrig/current
    cd /home/user/miners/xmrig
    
    sudo wget https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz
    sudo tar -xvf xmrig-6.25.0-linux-static-x64.tar.gz --strip-components=1
    sudo cp -v xmrig /home/user/miners/xmrig/current
else
    echo "xmrig already exists in current directory"
fi

TARGET_IMAGE="ubuntu:24.04"
TARGET_NAME="clore-default-"
# TARGET_NAME="octa_idle_job"

SCREEN_NAME="cpu"

START_CMD="/home/user/miners/xmrig/current/xmrig"

ARGS="-a rx/0 -o pool.supportxmr.com:9000 -u wallet-address -p 5950X-2-3070 -t 31 --cpu-affinity=0xFFFFFFFD --tls -k --http-host=127.0.0.1 --http-port=18080"

APPLY_OC="false"
RESET_OC="false"

#=============================================================================

if [[ -z "$START_CMD" ]]; then
    echo "$(date): START_CMD empty — refusing to start miner"
    exit 1
fi

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
    pkill -f "timeout.*docker events" 2>/dev/null || true
    
    exit 0
}

# Setup signal handlers
trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'handle_signal HUP' HUP

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
	
	# Apply GPU OC's if configured (for CPU-only mining this might not be needed, but kept for consistency)
    if [[ "${APPLY_OC,,}" == "true" ]]; then
        echo "$(date): Applying GPU clocks..."
        /usr/local/bin/gpu_apply_ocs.sh
    fi
    
	echo "$(date): Starting $SCREEN_NAME..."
    echo "$(date): Command: $START_CMD $ARGS"
    
    # Create PID file directory
    mkdir -p /tmp/miner_pids
    
    # Start in screen session
    screen -dmS "$SCREEN_NAME" bash -c \
        'echo "Miner starting at $(date)"; \
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
    
    # 4. Reset GPU if configured (for CPU-only mining this might not be needed)
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
#  DOCKER EVENT LOOP WITH RETRY
###############################################

echo "$(date): Starting Docker event monitor..."

# Main monitoring loop with restart on failure
while [[ $SHUTDOWN_REQUESTED -eq 0 ]]; do
    echo "$(date): Connecting to Docker events stream..."
    
    # Create a named pipe for docker events output
    PIPE_FILE="/tmp/docker_events_pipe_$$"
    mkfifo "$PIPE_FILE"
    
    # Start docker events with timestamp suppression
    docker events --format "{{.Type}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}" 2>&1 | \
        grep -v "^[A-Z][a-z][a-z] [A-Z][a-z][a-z] [0-9]" > "$PIPE_FILE" &
    
    DOCKER_EVENTS_PID=$!
    
    # Process events from the pipe
    while [[ $SHUTDOWN_REQUESTED -eq 0 ]] && read -r type action name image < "$PIPE_FILE" 2>/dev/null; do
        # Check if line contains actual event data (not error messages)
        if [[ -z "$type" ]] || [[ "$type" == *"error"* ]] || [[ "$type" == *"Error"* ]] || \
           [[ "$action" =~ ^[0-9] ]] || [[ "$name" =~ ^[0-9] ]] || [[ "$image" =~ ^[0-9] ]]; then
            # Skip error messages or malformed lines
            echo "$(date): Skipping malformed line or error: $type $action $name $image"
            continue
        fi
        
        # Log the event
        echo "$(date): Docker event - Type: $type, Action: $action, Name: $name, Image: $image"

        # Skip non-container events
        if [[ "$type" != "container" ]]; then
            echo "$(date): Skipping non-container event"
            continue
        fi

        # Name matching logic
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

        # Process only if image AND name match
        if [[ "$image" == "$TARGET_IMAGE" && "$name_match" -eq 1 ]]; then
            # Get actual container status for debugging
            actual_status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")
            echo "$(date): Current container status: $actual_status"

            case "$action" in
                start|create|unpause)
                    echo "$(date): START event detected → Wait for start to complete"
                    retry_count=0
                    started=false
                    
                    while [[ $retry_count -lt 10 && $SHUTDOWN_REQUESTED -eq 0 ]]; do
                        sleep 0.2
                        
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
                    
                    if [[ "$started" = false && $SHUTDOWN_REQUESTED -eq 0 ]]; then
                        echo "$(date): WARNING: Container $name never reached 'running' state after $retry_count attempts"
                        if ! docker inspect "$name" &>/dev/null; then
                            echo "$(date): Container $name no longer exists"
                        fi
                    fi
                    ;;

                kill|destroy|stop|die)
                    echo "$(date): STOP event detected ($action) → stop_miner"
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
                    echo "$(date): DEBUG: Unhandled action: $action for $name"
                    ;;
            esac
        fi
    done
    
    # Clean up the pipe
    rm -f "$PIPE_FILE" 2>/dev/null || true
    
    # Kill docker events process if still running
    if kill -0 "$DOCKER_EVENTS_PID" 2>/dev/null; then
        kill -TERM "$DOCKER_EVENTS_PID" 2>/dev/null
        wait "$DOCKER_EVENTS_PID" 2>/dev/null || true
    fi
    
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
sudo chmod +x /usr/local/bin/docker_events_cpu.sh

# Create systemd service for proper management
sudo tee /etc/systemd/system/docker-events-cpu.service > /dev/null <<'EOF'
[Unit]
Description=Docker Events CPU Miner Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_cpu.sh
ExecStart=/usr/local/bin/docker_events_cpu.sh
Restart=always
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=journal
StandardError=journal

# Allow up to 5 seconds for graceful shutdown
TimeoutStopSec=5
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable docker-events-cpu.service

# Start/Stop Service
sudo systemctl start docker-events-cpu.service
sudo systemctl stop docker-events-cpu.service

# check status
sudo systemctl status docker-events-cpu.service

# follow logs
sudo journalctl -u docker-events-cpu.service -f

# disable so it doesnt start on boot
sudo systemctl disable docker-events-cpu.service