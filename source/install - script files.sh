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
# FINAL PLACEHOLDER SUBSTITUTION (ONE TIME ONLY)
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

START_CMD=$(get_start_cmd "$MINER_NAME")

# Load from rig.conf
SCREEN_NAME=$(get_rig_conf "SCREEN_NAME" "0")

# If SCREEN_NAME is empty (""), ignore and use miner name
if [[ -z "$SCREEN_NAME" ]]; then
    SCREEN_NAME="$MINER_NAME"
fi

###############################################
#  FUNCTIONS
###############################################

# Function to start miner
start_miner() {
    if ! screen -list | grep -q "$SCREEN_NAME"; then
	    echo "$(date): Starting $SCREEN_NAME..."
		echo "$SCREEN_NAME" $START_CMD
		screen -dmS "$SCREEN_NAME" bash -c "$START_CMD"
        echo "Miner started in screen session: $SCREEN_NAME"
        echo "ARGS/OCS: $ARGS"
        echo "To view miner output: sudo screen -r $SCREEN_NAME"
    else
        echo "$(date): Miner already running in screen session: $SCREEN_NAME"
    fi
}
# Function to stop miner
stop_miner() {
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Stopping $SCREEN_NAME miner..."
        
        # Kill the screen session cleanly
        screen -S "$SCREEN_NAME" -X quit

        echo "Sleeping 5 seconds to allow miner to exit..."
        sleep 5

        if [[ "${RESET_OC,,}" == "true" ]]; then
            echo "Resetting GPU clocks and power limits..."
            /usr/local/bin/gpu_reset_poststop.sh
        fi
    else
        echo "$(date): No $SCREEN_NAME miner screen session found — nothing to stop."
    fi

    echo "Final sleep 5 seconds..."
    sleep 5
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
    local default_oc_file="/home/user/rig-cpu.conf"

    # Safe checks under set -u
    if [[ -n "${oc_file:-}" ]]; then
        cfg_file="$oc_file"
    elif [[ -n "${OC_FILE:-}" ]]; then
        cfg_file="$OC_FILE"
    else
        cfg_file="$default_oc_file"
    fi

    local key="$1"     # e.g., TARGET_IMAGE
    local gpu_id="$2"  # usually "0" in your examples

    # If file missing, return empty
    [[ ! -f "$cfg_file" ]] && echo "" && return

    local selected_value=""
    local file_key file_gpu rest_of_line value

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

# Load miner versions from rig.conf
XMRIG_VERSION=$(get_rig_conf "XMRIG_VERSION" "0")
BZMINER_VERSION=$(get_rig_conf "BZMINER_VERSION" "0")
WILDRIG_VERSION=$(get_rig_conf "WILDRIG_VERSION" "0")
SRBMINER_VERSION=$(get_rig_conf "SRBMINER_VERSION" "0")
RIGEL_VERSION=$(get_rig_conf "RIGEL_VERSION" "0")
LOLMINER_VERSION=$(get_rig_conf "LOLMINER_VERSION" "0")
ONEZEROMINER_VERSION=$(get_rig_conf "ONEZEROMINER_VERSION" "0")
GMINER_VERSION=$(get_rig_conf "GMINER_VERSION" "0")

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
