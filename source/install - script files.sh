mkdir -v /usr/local/bin/lib

sudo tee /usr/local/bin/docker_events_universal.sh > /dev/null <<'EOF'
#!/bin/bash

set -Eeuo pipefail
shopt -s inherit_errexit

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
# Default rig config resolution
# -------------------------------------------------
default_oc_file="/home/user/rig-cpu.conf"
readonly default_oc_file

if [[ -n "${oc_file:-}" ]]; then
    cfg_file="$oc_file"
elif [[ -n "${OC_FILE:-}" ]]; then
    cfg_file="$OC_FILE"
else
    cfg_file="$default_oc_file"
fi

CFG_FILE="$cfg_file"
export CFG_FILE

[[ -f "$CFG_FILE" ]] || {
    echo "Missing rig config: $CFG_FILE"
    exit 1
}

# -------------------------------------------------
# Miner config (required)
# -------------------------------------------------
: "${MINER_CONF:?MINER_CONF is not set}"
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
            echo "$current_args --api_listen=$api_host --api_port=$api_port"
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
ARGS=$(add_api_flags "$MINER_NAME" "$API_HOST" "$API_PORT" "$ARGS")

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
    
    local url="http://$API_HOST:$API_PORT"
    if [[ "$API_HOST" == "0.0.0.0" ]]; then
        url="http://127.0.0.1:$API_PORT"
    fi
    
    echo "$(date): Checking API health at $url..."
    
    # Try to reach the API endpoint
    if curl -s --max-time 5 "$url" > /dev/null 2>&1; then
        echo "$(date): API is responding"
        return 0
    else
        echo "$(date): API is not responding"
        return 1
    fi
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
    # Check for zombie sessions first
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Screen session exists for $SCREEN_NAME - checking if miner is alive..."
        
        local pid_file="/tmp/${SCREEN_NAME}_miner.pid"
        if [[ -f "$pid_file" ]]; then
            local miner_pid=$(cat "$pid_file")
            
            if ! ps -p "$miner_pid" > /dev/null 2>&1; then
                echo "$(date): Miner process is dead but screen session exists - cleaning up..."
                stop_miner
                echo "$(date): Starting fresh miner after cleanup..."
            else
                echo "$(date): Miner already running in screen session: $SCREEN_NAME"
                echo "$(date): To view: sudo screen -r $SCREEN_NAME"
                return
            fi
        fi
    fi
    
    # Start fresh miner
    echo "$(date): Starting $SCREEN_NAME..."
    echo "$(date): API: $API_HOST:$API_PORT"
    echo "$(date): Command: $START_CMD"
    
    # Create PID file directory
    mkdir -p /tmp/miner_pids
    
    # Start in screen session
    screen -dmS "$SCREEN_NAME" bash -c \
        "echo 'Miner starting at \$(date)'; \
         echo 'API: $API_HOST:$API_PORT'; \
         echo '\$BASHPID' > '/tmp/${SCREEN_NAME}_miner.pid'; \
         trap 'echo \"Miner exiting at \$(date)\"; rm -f \"/tmp/${SCREEN_NAME}_miner.pid\"' EXIT; \
         $START_CMD"
    
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
    else
        echo "$(date): ERROR: Failed to start screen session!"
        return 1
    fi
}

# Function to stop miner (clean closure first)
stop_miner() {
    echo "$(date): Stopping $SCREEN_NAME miner (clean shutdown)..."
    
    # 1. FIRST ATTEMPT: Clean screen quit (let miner cleanup)
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Sending clean quit to screen session..."
        screen -S "$SCREEN_NAME" -X quit
        
        echo "$(date): Waiting 5 seconds for miner cleanup..."
        sleep 5
    else
        echo "$(date): No $SCREEN_NAME screen session found."
    fi
    
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

        case "$action" in

            start|create|unpause)
                echo "$(date): START event detected → start_miner"
                start_miner
                ;;

            pause|kill|destroy|stop|die)
                echo "$(date): STOP event detected → checking container"
                if ! check_target_container; then
                    stop_miner
                fi
                ;;

            *)
                # Ignore irrelevant Docker events
                ;;
        esac
    fi
done
EOF

sudo tee /usr/local/bin/lib/00-get_rig_conf.sh > /dev/null <<'EOF'
get_rig_conf() {

    local key=""
    local gpu_id=""
    local cfg_file=""

    # -------------------------------------------------
    # Signature normalization
    #
    # get_rig_conf KEY GPU
    # get_rig_conf FILE KEY GPU
    # -------------------------------------------------
    if [[ $# -eq 2 ]]; then
        cfg_file="$CFG_FILE"
        key="$1"
        gpu_id="$2"
    elif [[ $# -eq 3 ]]; then
        cfg_file="$1"
        key="$2"
        gpu_id="$3"
    else
        echo "[get_rig_conf] Invalid arguments" >&2
        return 1
    fi

    [[ -f "$cfg_file" ]] || { echo ""; return; }

    local selected_value=""
    local file_key file_gpu rest value

    # Read key, gpu, and rest of line into rest_of_line
    while read -r file_key file_gpu rest_of_line; do

        # Skip empty or comment lines
        [[ -z "$file_key" || "$file_key" =~ ^# ]] && continue

        # Skip non-matching keys
        [[ "$file_key" != "$key" ]] && continue

        # Everything after 2nd column is the value
        value="$rest_of_line"

        # Remove surrounding quotes
        value="${value#\"}"
        value="${value%\"}"

        # GPU-specific match overrides ALL
        if [[ "$file_gpu" == "$gpu_id" ]]; then
            selected_value="$value"
            break
        fi

        # ALL fallback
        if [[ "$file_gpu" == "ALL" ]]; then
            selected_value="$value"
        fi

    done < "$cfg_file"

    echo "$selected_value"
}
EOF
sudo tee /usr/local/bin/lib/01-miner_install.sh > /dev/null <<'EOF'
###############################################
#  MINER INSTALL
###############################################

###########################################
# CONFIG — Where all miners will be stored
###########################################

# Load miner versions from miner.conf
XMRIG_VERSION=$(get_rig_conf "$MINER_CONF" "XMRIG_VERSION" "0")
BZMINER_VERSION=$(get_rig_conf "$MINER_CONF" "BZMINER_VERSION" "0")
WILDRIG_VERSION=$(get_rig_conf "$MINER_CONF" "WILDRIG_VERSION" "0")
SRBMINER_VERSION=$(get_rig_conf "$MINER_CONF" "SRBMINER_VERSION" "0")
RIGEL_VERSION=$(get_rig_conf "$MINER_CONF" "RIGEL_VERSION" "0")
LOLMINER_VERSION=$(get_rig_conf "$MINER_CONF" "LOLMINER_VERSION" "0")
ONEZEROMINER_VERSION=$(get_rig_conf "$MINER_CONF" "ONEZEROMINER_VERSION" "0")
GMINER_VERSION=$(get_rig_conf "$MINER_CONF" "GMINER_VERSION" "0")

echo ""
echo "==============================================="
echo "  Miner Versions Loaded from rig.conf"
echo "==============================================="
echo "  XMRig:        $XMRIG_VERSION"
echo "  BzMiner:      $BZMINER_VERSION"
echo "  WildRig:      $WILDRIG_VERSION"
echo "  SRBMiner:     $SRBMINER_VERSION"
echo "  Rigel:        $RIGEL_VERSION"
echo "  lolMiner:     $LOLMINER_VERSION"
echo "  OneZeroMiner: $ONEZEROMINER_VERSION"
echo "  GMiner:       $GMINER_VERSION"
echo "==============================================="
echo ""

###########################################
# Helper — Download with retries
###########################################
download_with_retry() {
    local outfile="$1"
    local url="$2"

    for attempt in 1 2 3; do
        echo "  [Attempt $attempt] Downloading: $url"
        if wget -q "$url" -O "$outfile"; then
            if [ -s "$outfile" ]; then return 0; fi
        fi
        echo "  Download failed, retrying..."
        sleep 2
    done

    echo "ERROR: Could not download $url"
    return 1
}

###########################################
# Helper — Remove older versions
###########################################
cleanup_old_versions() {
    local miner="$1"
    local keep="$2"

    local folder="$BASE_DIR/$miner"
    [ -d "$folder" ] || return 0

    for dir in "$folder"/*; do
        [[ "$dir" == "$folder/current" ]] && continue
        [[ "$dir" == "$folder/$keep" ]] && continue
        echo "  Removing old version: $dir"
        rm -rf "$dir"
    done
}

###########################################
# Helper — Generic installer
###########################################
install_miner() {
    local name="$1"
    local version="$2"
    local url="$3"
    local file="$4"
    local strip="$5"
    local bin_name="$6"

    local miner_dir="$BASE_DIR/$name/$version"
    local bin_path="$miner_dir/$bin_name"

    if [ ! -f "$bin_path" ]; then
        echo ""
        echo "==== Installing $name $version ===="
        rm -rf "$miner_dir"
        mkdir -p "$miner_dir"
        cd "$miner_dir"

        download_with_retry "$file" "$url"

        echo "  Extracting..."
        if ! tar -xf "$file" $strip; then
            echo "ERROR: Extraction failed — file likely invalid."
            rm -f "$file"
            exit 1
        fi
        rm -f "$file"

        if [ ! -f "$bin_name" ]; then
            echo "ERROR: Expected binary '$bin_name' not found!"
            exit 1
        fi
    else
        echo ""
        echo "$name $version already installed (found $bin_name), skipping."
    fi

    ln -sfn "$miner_dir" "$BASE_DIR/$name/current"
    echo "  Symlink: $BASE_DIR/$name/current -> $miner_dir"

    cleanup_old_versions "$name" "$version"
}

###########################################
# Install: XMRIG
###########################################
XMRIG_TAR="xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz"
install_miner "xmrig" "$XMRIG_VERSION" \
  "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/${XMRIG_TAR}" \
  "$XMRIG_TAR" "--strip-components=1" "xmrig"


###########################################
# Install: WildRig
###########################################
WILDRIG_TAR="wildrig-multi-linux-${WILDRIG_VERSION}.tar.gz"
install_miner "wildrig" "$WILDRIG_VERSION" \
  "https://github.com/andru-kun/wildrig-multi/releases/download/${WILDRIG_VERSION}/${WILDRIG_TAR}" \
  "$WILDRIG_TAR" "" "wildrig-multi"


###########################################
# Install: BzMiner
###########################################
BZ_TAR="bzminer_${BZMINER_VERSION}_linux.tar.gz"
install_miner "bzminer" "$BZMINER_VERSION" \
  "https://github.com/bzminer/bzminer/releases/download/${BZMINER_VERSION}/${BZ_TAR}" \
  "$BZ_TAR" "--strip-components=1" "bzminer"


###########################################
# Install: SRBMiner
###########################################
SRB_DASH="${SRBMINER_VERSION//./-}"
SRB_TAR="SRBMiner-Multi-${SRB_DASH}-Linux.tar.gz"
install_miner "srbminer" "$SRBMINER_VERSION" \
  "https://github.com/doktor83/SRBMiner-Multi/releases/download/${SRBMINER_VERSION}/${SRB_TAR}" \
  "$SRB_TAR" "--strip-components=1" "SRBMiner-MULTI"


###########################################
# Install: Rigel
###########################################
RIGEL_TAR="rigel-${RIGEL_VERSION}-linux.tar.gz"
install_miner "rigel" "$RIGEL_VERSION" \
  "https://github.com/rigelminer/rigel/releases/download/${RIGEL_VERSION}/${RIGEL_TAR}" \
  "$RIGEL_TAR" "--strip-components=1" "rigel"


###########################################
# Install: lolMiner
###########################################
LOL_TAR="lolMiner_v${LOLMINER_VERSION}_Lin64.tar.gz"
install_miner "lolminer" "$LOLMINER_VERSION" \
  "https://github.com/Lolliedieb/lolMiner-releases/releases/download/${LOLMINER_VERSION}/${LOL_TAR}" \
  "$LOL_TAR" "--strip-components=1" "lolMiner"


###########################################
# Install: OneZeroMiner (correct Linux build)
###########################################
ONEZERO_TAR="onezerominer-linux-${ONEZEROMINER_VERSION}.tar.gz"
install_miner "onezerominer" "$ONEZEROMINER_VERSION" \
  "https://github.com/OneZeroMiner/OneZeroMiner/releases/download/v${ONEZEROMINER_VERSION}/${ONEZERO_TAR}" \
  "$ONEZERO_TAR" "--strip-components=1" "onezerominer"


###########################################
# Install: GMiner
###########################################
GM_U="${GMINER_VERSION//./_}"
GM_TAR="gminer_${GM_U}_linux64.tar.xz"
install_miner "gminer" "$GMINER_VERSION" \
  "https://github.com/develsoftware/GMinerRelease/releases/download/${GMINER_VERSION}/${GM_TAR}" \
  "$GM_TAR" "" "miner"


###########################################
# Export paths
###########################################
cat <<EXPORTS > "$BASE_DIR/miner_paths.env"
# Source this file:
#   source "$BASE_DIR/miner_paths.env"

XMRIG_BIN="$BASE_DIR/xmrig/current/xmrig"
WILDRIG_BIN="$BASE_DIR/wildrig/current/wildrig-multi"
BZMINER_BIN="$BASE_DIR/bzminer/current/bzminer"
SRBMINER_BIN="$BASE_DIR/srbminer/current/SRBMiner-MULTI"
RIGEL_BIN="$BASE_DIR/rigel/current/rigel"
LOLMINER_BIN="$BASE_DIR/lolminer/current/lolMiner"
ONEZEROMINER_BIN="$BASE_DIR/onezerominer/current/onezerominer"
GMINER_BIN="$BASE_DIR/gminer/current/miner"
EXPORTS

echo ""
echo "Miner paths saved to: $BASE_DIR/miner_paths.env"
echo "Load them with: source $BASE_DIR/miner_paths.env"

source $BASE_DIR/miner_paths.env
EOF
sudo tee /usr/local/bin/lib/02-load_configs.sh > /dev/null <<'EOF'
###############################################
#  CONFIG
###############################################
# ---------------------------------------------------
# get_miner_bin <miner_name>
# Returns the correct binary path using existing *_BIN vars
# ---------------------------------------------------
get_miner_bin() {
    local name="$1"

    local custom=$(get_rig_conf "CUSTOM_MINER" "0")
    if [[ -n "$custom" ]]; then
        echo "$custom"
        return
    fi

    case "$name" in
        bzminer)      echo "$BZMINER_BIN" ;;
        wildrig)      echo "$WILDRIG_BIN" ;;
        xmrig)        echo "$XMRIG_BIN" ;;
        srbminer)     echo "$SRBMINER_BIN" ;;
        rigel)        echo "$RIGEL_BIN" ;;
        lolminer)     echo "$LOLMINER_BIN" ;;
        onezerominer) echo "$ONEZEROMINER_BIN" ;;
        gminer)       echo "$GMINER_BIN" ;;
        *)
            echo "$(date): Unknown miner '$name' — defaulting to bzminer" >&2
            echo "$BZMINER_BIN"
            ;;
    esac
}

get_start_cmd() {
    local name="$1"
    local cmd=""

    # ---------------------------------------------------------
    # CUSTOM MINER OVERRIDE
    # If CUSTOM_MINER is set in rig.conf:
    #   CUSTOM_MINER ALL "/path/to/customminer"
    #
    # Then build the command as:
    #   /path/to/customminer $ARGS
    #
    # No templates, no auto-flags — full manual control.
    # ---------------------------------------------------------
    local custom=$(get_rig_conf "CUSTOM_MINER" "0")
    if [[ -n "$custom" ]]; then
        cmd="$custom $ARGS"
        echo "$cmd"
        return
    fi

    # ---------------------------------------------------------
    # NORMAL BUILT-IN MINER COMMAND TEMPLATES
    # ---------------------------------------------------------
    case "$name" in

        bzminer)
            cmd="$MINER_BIN -a $ALGO -p $POOL -w $WALLET --pool_password $PASS $ARGS"
            ;;

        wildrig)
            cmd="$MINER_BIN --algo $ALGO --url $POOL --user $WALLET --pass $PASS $ARGS"
            ;;

        xmrig)
            cmd="$MINER_BIN -a $ALGO -o $POOL -u $WALLET -p $PASS $ARGS"
            ;;

        srbminer)
            cmd="$MINER_BIN --algorithm $ALGO --pool $POOL --wallet $WALLET --password $PASS $ARGS"
            ;;

        rigel)
            cmd="$MINER_BIN -a $ALGO -o $POOL -u $WALLET -p $PASS $ARGS"
            ;;

        lolminer)
            cmd="$MINER_BIN --algo $ALGO --pool $POOL --user $WALLET --pass $PASS $ARGS"
            ;;

        onezerominer)
            cmd="$MINER_BIN --algo $ALGO --pool $POOL --wallet $WALLET --pass $PASS $ARGS"
            ;;

        gminer)
            cmd="$MINER_BIN --algo $ALGO --server $POOL --user $WALLET --pass $PASS $ARGS"
            ;;
        *)
            echo "[ERROR] Unknown miner: $name" >&2
            return
            ;;
    esac

    echo "$cmd"
}


# Worker name from hostname, normalized
WORKER_NAME="$(cat /etc/hostname)"
WORKER_NAME="${WORKER_NAME//x/X}"
WORKER_NAME="${WORKER_NAME//t/T}"

TARGET_IMAGE=$(get_rig_conf "TARGET_IMAGE" "0")
TARGET_NAME=$(get_rig_conf "TARGET_NAME" "0")

RESET_OC=$(get_rig_conf "RESET_OC" "0")

MINER_NAME=$(get_rig_conf "MINER" "0")

if [[ -z "$MINER_NAME" ]]; then
    echo "$(date): MINER not set in rig.conf, defaulting to bzminer"
    MINER_NAME="bzminer"
fi

MINER_BIN=$(get_miner_bin "$MINER_NAME")

echo "[miner] $MINER_BIN"

ALGO=$(get_rig_conf "ALGO" "0")
ARGS=$(get_rig_conf "ARGS" "0")

###############################################
#  MINER SETTINGS
###############################################

POOL=$(get_rig_conf "POOL" "0")
WALLET=$(get_rig_conf "WALLET" "0")
PASS=$(get_rig_conf "PASS" "0")
EOF

sudo tee /usr/local/bin/lib/03-cpu_threads.sh > /dev/null <<'EOF'
TOTAL_THREADS=$(nproc)
CPU_THREADS=$((TOTAL_THREADS - 1))

# Defaults
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
EOF
sudo tee /usr/local/bin/lib/04-algo_config.sh > /dev/null <<'EOF'
WARTHOG_TARGET=""

if [[ "$ALGO" == "warthog" ]]; then
    if (( TOTAL_THREADS >= 32 )); then
        WARTHOG_TARGET=47000000
    elif (( TOTAL_THREADS >= 24 )); then
        WARTHOG_TARGET=37000000
    else
        WARTHOG_TARGET=30000000
    fi
fi

EOF
ls -lh /usr/local/bin/lib/
