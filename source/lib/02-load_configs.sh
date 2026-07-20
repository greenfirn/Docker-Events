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

    # CUSTOM_MINER holds just the binary filename, installed by
    # 01-miner_install.sh (from CUSTOM_MINER_URL) into
    # $BASE_DIR/<bin_name>/<version>, symlinked at $BASE_DIR/<bin_name>/current
    # (keyed by the binary name itself, so multiple custom miners can coexist).
    local custom=$(get_rig_conf "CUSTOM_MINER" "0")
    if [[ -n "$custom" && "$custom" != "0" ]]; then
        echo "$BASE_DIR/$custom/current/$custom"
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
            echo "$(date): ERROR — Unknown miner '$name', no binary path available" >&2
            echo ""
            ;;
    esac
}

get_start_cmd() {
    local name="$1"
    local cmd=""

    # ---------------------------------------------------------
    # CUSTOM MINER OVERRIDE
    # If CUSTOM_MINER is set in rig.conf:
    #   CUSTOM_MINER 0 "miner-binary-name"
    #
    # CUSTOM_MINER is just the binary filename produced by
    # 01-miner_install.sh from CUSTOM_MINER_URL. The full command is:
    #   $BASE_DIR/<binary-name>/current/<binary-name> $ARGS
    #
    # No templates, no auto-flags — full manual control via ARGS.
    # ---------------------------------------------------------
    local custom=$(get_rig_conf "CUSTOM_MINER" "0")
    if [[ -n "$custom" && "$custom" != "0" ]]; then
        cmd="$BASE_DIR/$custom/current/$custom $ARGS"
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
WORKER_NAME="${WORKER_NAME//s/S}"


TARGET_IMAGE=$(get_rig_conf "TARGET_IMAGE" "0")
TARGET_NAME=$(get_rig_conf "TARGET_NAME" "0")

APPLY_OC=$(get_rig_conf "APPLY_OC" "0")
RESET_OC=$(get_rig_conf "RESET_OC" "0")

MINER_NAME=$(get_rig_conf "MINER" "0")
CUSTOM_MINER=$(get_rig_conf "CUSTOM_MINER" "0")

if [[ -n "$CUSTOM_MINER" && "$CUSTOM_MINER" != "0" ]]; then
    # CUSTOM_MINER overrides everything - skip the normal MINER/MINER_BIN
    # resolution checks entirely, since get_miner_bin() and get_start_cmd()
    # both already short-circuit on CUSTOM_MINER regardless of MINER_NAME.
    #
    # CUSTOM_MINER holds just the binary filename (installed by
    # 01-miner_install.sh from CUSTOM_MINER_URL into $BASE_DIR/<bin_name>/<version>,
    # symlinked at $BASE_DIR/<bin_name>/current) — not a full path. Keyed by the
    # binary name itself so multiple custom miners can coexist side by side.
    echo "[miner] CUSTOM_MINER set — skipping built-in miner name/binary checks"
    MINER_BIN="$BASE_DIR/$CUSTOM_MINER/current/$CUSTOM_MINER"

    if [[ ! -f "$MINER_BIN" ]]; then
        echo "$(date): ERROR — CUSTOM_MINER binary not found at '$MINER_BIN'. Did 01-miner_install.sh run with CUSTOM_MINER_URL set?" >&2
        return 1 2>/dev/null || exit 1
    fi
else
    if [[ -z "$MINER_NAME" ]]; then
        echo "$(date): ERROR — MINER not set in rig.conf. Please set MINER ALL <miner_name>, or set CUSTOM_MINER instead." >&2
        return 1 2>/dev/null || exit 1
    fi

    MINER_BIN=$(get_miner_bin "$MINER_NAME")

    if [[ -z "$MINER_BIN" ]]; then
        echo "$(date): ERROR — Could not resolve a binary path for MINER='$MINER_NAME'. Aborting." >&2
        return 1 2>/dev/null || exit 1
    fi
fi

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
