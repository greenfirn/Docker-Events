# stop old services
sudo systemctl stop docker_events_gpu.service
sudo systemctl stop docker_events_cpu.service
sudo systemctl stop docker_events.service

# disable so it doesnt run on reboot
sudo systemctl disable docker_events_gpu.service
sudo systemctl disable docker_events_cpu.service
sudo systemctl disable docker_events.service

#========================================================================================================
#========================================================================================================

# -- write docker_events_universal script --
#sudo tee /usr/local/bin/docker_events_universal.sh > /dev/null <<'EOF'
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
#EOF

# service makes executable on start

#========================================================================================================
#========================================================================================================

# let daemon know about changes
sudo systemctl daemon-reload

# enable so it starts on boot, start service
sudo systemctl enable docker_events_gpu.service
sudo systemctl start docker_events_gpu.service

# follow service logs
sudo journalctl -u docker_events_gpu.service -f


sudo systemctl enable docker_events_cpu.service
sudo systemctl start docker_events_cpu.service

sudo journalctl -u docker_events_cpu.service -f

# check service status
sudo systemctl status docker_events_gpu.service
sudo systemctl status docker_events_cpu.service