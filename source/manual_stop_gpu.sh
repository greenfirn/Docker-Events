sudo tee /usr/local/bin/manual_stop_gpu.sh > /dev/null <<'EOF'
#!/bin/bash

set -Eeuo pipefail
shopt -s inherit_errexit

echo "========================================"
echo "MANUAL MINER STOP SCRIPT"
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

# -------------------------------------------------
# Load miner paths environment
# -------------------------------------------------
if [[ -f "$BASE_DIR/miner_paths.env" ]]; then
    echo "[init] Loading miner paths from: $BASE_DIR/miner_paths.env"
    source "$BASE_DIR/miner_paths.env"
else
    echo "[init] WARNING: miner_paths.env not found at $BASE_DIR/miner_paths.env"
    echo "[init] Miner binary locations may not be set correctly"
fi

# Check config files exist
[[ -f "$CFG_FILE" ]] || {
    echo "Missing rig config: $CFG_FILE"
    exit 1
}

[[ -f "$MINER_CONF" ]] || {
    echo "Missing miner.conf: $MINER_CONF"
    exit 1
}

# -------------------------------------------------
# Source libraries (only needed ones for stop)
# -------------------------------------------------
for f in \
    "$SCRIPT_DIR/lib/00-get_rig_conf.sh" \
    "$SCRIPT_DIR/lib/02-load_configs.sh" \
    "$SCRIPT_DIR/lib/04-algo_config.sh"
do
    [[ -f "$f" ]] || { echo "Missing include: $f"; exit 1; }
    source "$f"
done

# Load from rig.conf
SCREEN_NAME=$(get_rig_conf "SCREEN_NAME" "0")

# Remove quotes if present
SCREEN_NAME="${SCREEN_NAME//\"/}"

# If SCREEN_NAME is empty (""), ignore and use miner name
if [[ -z "$SCREEN_NAME" ]]; then
    SCREEN_NAME="$MINER_NAME"
fi

# -------------------------------------------------
# Get OC settings from rig.conf
# -------------------------------------------------
RESET_OC=$(get_rig_conf "RESET_OC" "0")

# Remove quotes if present
RESET_OC="${RESET_OC//\"/}"

# Convert to lowercase for comparison
RESET_OC="${RESET_OC,,}"

# Default to false if empty
: "${RESET_OC:=false}"

echo "Miner Name:      $MINER_NAME"
echo "Screen Session:  $SCREEN_NAME"
echo "Reset GPU on stop: $RESET_OC"
echo "========================================"

# ---------------------------------------------------------
# PID-BASED KILL FUNCTION
# ---------------------------------------------------------
kill_by_pid() {
    local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
    
    if [[ -f "$pid_file" ]]; then
        local miner_pid=$(cat "$pid_file")
        
        if ps -p "$miner_pid" > /dev/null 2>&1; then
            echo "[$(date)] WARNING: Miner process still alive after screen quit - forcing kill (PID: $miner_pid)..."
            
            # Send SIGTERM first (graceful)
            kill -15 "$miner_pid" 2>/dev/null
            sleep 2
            
            # Force kill if still running
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "[$(date)] Miner not responding to SIGTERM - sending SIGKILL..."
                kill -9 "$miner_pid" 2>/dev/null
                sleep 1
            fi
            
            # Kill any child processes
            pkill -P "$miner_pid" 2>/dev/null 2>&1 || true
            
            echo "[$(date)] Miner process $miner_pid terminated (forcefully)"
        fi
        
        # Clean up PID file
        rm -f "$pid_file"
    fi
}

# ---------------------------------------------------------
# STOP MINER FUNCTION
# ---------------------------------------------------------
stop_miner() {
    echo "[$(date)] Stopping $SCREEN_NAME miner..."
    
    # Check if screen session exists at all
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "[$(date)] Screen session found for $SCREEN_NAME"
        
        # 1. FIRST ATTEMPT: Clean screen quit (let miner cleanup)
        echo "[$(date)] Sending clean quit to screen session..."
        screen -S "$SCREEN_NAME" -X quit
        
        echo "[$(date)] Waiting 5 seconds for miner cleanup..."
        sleep 5
        
        # 2. CHECK: If miner process still exists after clean quit
        local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
        if [[ -f "$pid_file" ]]; then
            local miner_pid=$(cat "$pid_file")
            
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "[$(date)] Miner still running after screen quit - using force cleanup..."
                kill_by_pid
            else
                echo "[$(date)] Miner exited cleanly after screen quit."
                rm -f "$pid_file"
            fi
        fi
        
        # 3. CLEANUP: Any leftover screen processes
        local screen_pids=$(pgrep -f "SCREEN.*$SCREEN_NAME" 2>/dev/null || true)
        if [[ -n "$screen_pids" ]]; then
            echo "[$(date)] Cleaning up leftover screen processes..."
            kill -15 $screen_pids 2>/dev/null
            sleep 2
            kill -9 $screen_pids 2>/dev/null 2>&1 || true
        fi
        
        # 4. Final verification for screen session
        echo "[$(date)] Verifying cleanup..."
        
        if screen -list | grep -q "$SCREEN_NAME"; then
            echo "[$(date)] WARNING: Screen session still exists!"
            
            # Try one more forceful cleanup
            echo "[$(date)] Attempting forceful cleanup..."
            screen -ls | grep "$SCREEN_NAME" | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null || true
            sleep 2
            
            if screen -list | grep -q "$SCREEN_NAME"; then
                echo "[$(date)] ERROR: Could not remove screen session!"
                # Continue to reset GPU anyway
            else
                echo "[$(date)] Screen session forcefully removed."
            fi
        else
            echo "[$(date)] Screen session cleaned up successfully."
        fi
        
        # Clean PID file if still exists
        rm -f "/tmp/${SCREEN_NAME}_miner.pid"
        
    else
        echo "[$(date)] No $SCREEN_NAME screen session found."
        
        # Check if PID file exists (orphaned process)
        local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
        if [[ -f "$pid_file" ]]; then
            local miner_pid=$(cat "$pid_file")
            if ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "[$(date)] Found orphaned miner process (PID: $miner_pid) - cleaning up..."
                kill_by_pid
            else
                echo "[$(date)] Removing stale PID file..."
                rm -f "$pid_file"
            fi
        else
            echo "[$(date)] No PID file found."
        fi
    fi
    
    # 5. Reset GPU if configured (always run this if RESET_OC is true)
    if [[ "${RESET_OC,,}" == "true" ]]; then
        echo "[$(date)] Resetting GPU clocks and power limits..."
        /usr/local/bin/gpu_reset_poststop.sh
    fi
    
    echo "[$(date)] Final sleep 2 seconds..."
    sleep 2
    
    echo "========================================"
    echo "MINER STOPPED SUCCESSFULLY"
    echo "========================================"
}

# ---------------------------------------------------------
# MAIN STOP LOGIC
# ---------------------------------------------------------
# Check if miner is running first
if screen -list | grep -q "$SCREEN_NAME"; then
    echo "Miner is currently running in screen session: $SCREEN_NAME"
    
    # Check for PID file
    if [[ -f "/tmp/${SCREEN_NAME}_miner.pid" ]]; then
        miner_pid=$(cat "/tmp/${SCREEN_NAME}_miner.pid")
        if ps -p "$miner_pid" > /dev/null 2>&1; then
            echo "Active PID: $miner_pid"
        fi
    fi
    
    stop_miner
else
    echo "Miner is not currently running in a screen session."
    echo "check for orphaned miner process"
	stop_miner
fi
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/manual_stop_gpu.sh