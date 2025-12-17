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
            cmd="$MINER_BIN -a $ALGO -w $WALLET -p $POOL $ARGS"
            ;;

        wildrig)
            cmd="$MINER_BIN --algo $ALGO --user $WALLET --url $POOL --pass $PASS $ARGS"
            ;;

        xmrig)
            cmd="$MINER_BIN -a $ALGO -u $WALLET -o $POOL -p $PASS $ARGS"
            ;;

        srbminer)
            cmd="$MINER_BIN --algorithm $ALGO --pool $POOL --wallet $WALLET $ARGS"
            ;;

        rigel)
            cmd="$MINER_BIN -a $ALGO -o $POOL -u $WALLET $ARGS"
            ;;

        lolminer)
            cmd="$MINER_BIN --algo $ALGO --pool $POOL --user $WALLET $ARGS"
            ;;

        onezerominer)
            cmd="$MINER_BIN --algo $ALGO --server $POOL --user $WALLET $ARGS"
            ;;

        gminer)
            cmd="$MINER_BIN --algo $ALGO --server $POOL --user $WALLET $ARGS"
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



if [[ "$ALGO" == "warthog" ]]; then
    echo "Using warthog settings"
    # Compute Warthog target
    if [ "$TOTAL_THREADS" -ge 32 ]; then
        WARTHOG_TARGET=47000000
    elif [ "$TOTAL_THREADS" -ge 24 ]; then
        WARTHOG_TARGET=37000000
    else
        WARTHOG_TARGET=30000000
    fi
	
	ARGS="${ARGS//%WARTHOG_TARGET%/$WARTHOG_TARGET}"
fi

###############################################
#  MINER SETTINGS
###############################################

POOL=$(get_rig_conf "POOL" "0")
WALLET=$(get_rig_conf "WALLET" "0")
PASS=$(get_rig_conf "PASS" "0")

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