sudo mkdir -v /usr/local/bin/lib

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
TEAMREDMINER_VERSION=$(get_rig_conf "$MINER_CONF" "TEAMREDMINER_VERSION" "0")
TREXMINER_VERSION=$(get_rig_conf "$MINER_CONF" "TREXMINER_VERSION" "0")

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
echo "  TeamRedMiner: $TEAMREDMINER_VERSION"
echo "  T-Rex Miner:  $TREXMINER_VERSION"
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
# Install: TeamRedMiner
###########################################
TEAMRED_TAR="teamredminer-v${TEAMREDMINER_VERSION}-linux.tgz"
install_miner "teamredminer" "$TEAMREDMINER_VERSION" \
  "https://github.com/todxx/teamredminer/releases/download/v${TEAMREDMINER_VERSION}/${TEAMRED_TAR}" \
  "$TEAMRED_TAR" "--strip-components=1" "teamredminer"

###########################################
# Install: T-Rex Miner
###########################################
TREX_TAR="t-rex-${TREXMINER_VERSION}-linux.tar.gz"
install_miner "trexminer" "$TREXMINER_VERSION" \
  "https://github.com/trexminer/T-Rex/releases/download/${TREXMINER_VERSION}/${TREX_TAR}" \
  "$TREX_TAR" "" "t-rex"

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
TEAMREDMINER_BIN="$BASE_DIR/teamredminer/current/teamredminer"
TREXMINER_BIN="$BASE_DIR/trexminer/current/t-rex"
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
        teamredminer) echo "$TEAMREDMINER_BIN" ;;
		trex)         echo "$TREXMINER_BIN" ;;
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
        teamredminer)
            cmd="$MINER_BIN -a $ALGO -o $POOL -u $WALLET -p $PASS $ARGS"
            ;;
        trex)
            cmd="$MINER_BIN -a $ALGO -o $POOL -u $WALLET -p $PASS $ARGS"
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

APPLY_OC=$(get_rig_conf "APPLY_OC" "0")
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
