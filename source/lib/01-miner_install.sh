
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
EXPORTS

echo ""
echo "Miner paths saved to: $BASE_DIR/miner_paths.env"
echo "Load them with: source $BASE_DIR/miner_paths.env"

source $BASE_DIR/miner_paths.env

