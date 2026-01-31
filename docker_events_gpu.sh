# stop old services
sudo systemctl stop docker_events_gpu.service
sudo systemctl stop docker_events_cpu.service

# disable so it doesnt run on boot
sudo systemctl disable docker_events_gpu.service
sudo systemctl disable docker_events_cpu.service

# -- write docker_events_gpu script --

sudo mkdir -v /usr/local/bin

sudo tee /usr/local/bin/docker_events_gpu.sh > /dev/null <<'EOF'
#!/bin/bash

set -euo pipefail

#======= Miner Start Settings ================================================

# remove rigel to update
# sudo rm -rv /home/user/miners/rigel

if [ ! -f "/home/user/miners/rigel/current/rigel" ]; then
    sudo mkdir -p /home/user/miners/rigel/current
    cd /home/user/miners/rigel
    
    sudo wget https://github.com/rigelminer/rigel/releases/download/1.23.1/rigel-1.23.1-linux.tar.gz
    sudo tar -xvf rigel-1.23.1-linux.tar.gz --strip-components=1
    sudo cp -v rigel /home/user/miners/rigel/current
else
    echo "rigel already exists in current directory"
fi

TARGET_IMAGE="ubuntu:24.04"
TARGET_NAME="clore-default-"
# TARGET_NAME="octa_idle_job"

SCREEN_NAME="gpu"

START_CMD="/home/user/miners/rigel/current/rigel"

ARGS="-a kawpow -o stratum+ssl://ca.quai.herominers.com:1185 -o stratum+ssl://us2.quai.herominers.com:1185 -u wallet-address -p x -w 5950X-2-3070 --api-bind 127.0.0.1:5000"

APPLY_OC="false"
RESET_OC="false"

#=============================================================================

if [[ -z "$START_CMD" ]]; then
    echo "$(date): START_CMD empty — refusing to start miner"
    return
fi

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
#  DOCKER EVENT LOOP
###############################################

echo "$(date): Starting Docker event monitor..."

docker events --format "{{.Type}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}" | \
while read type action name image; do

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
	    
		# Get actual container status for debugging
        actual_status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")
        echo "$(date): Current container status: $actual_status"

    case "$action" in
        start|create|unpause)
            echo "$(date): START event detected → Wait for start to complete"
            retry_count=0
            started=false
            
            while [ $retry_count -lt 10 ]; do  # Increased retries for start operations
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
            if [ "$started" = false ]; then
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
            
            while [ $retry_count -lt 5 ]; do
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
            if [ $retry_count -eq 5 ]; then
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
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/docker_events_gpu.sh

# -- write GPU service --

sudo tee /etc/systemd/system/docker-events-gpu.service > /dev/null <<'EOF'
[Unit]
Description=docker_events_gpu Watchdog
After=docker.service
After=nvidia-persistenced.service
Requires=docker.service

[Service]
User=root
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_gpu.sh
ExecStart=/usr/local/bin/docker_events_gpu.sh
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
Restart=always
RestartSec=2
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable docker-events-gpu.service

# Start/Stop Service
sudo systemctl start docker-events-gpu.service
sudo systemctl stop docker-events-gpu.service

# check status
sudo systemctl status docker-events-gpu.service

# follow logs
sudo journalctl -u docker-events-gpu.service -f

# disable so it doesnt start on boot
sudo systemctl disable docker-events-gpu.service