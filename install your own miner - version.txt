# -- write docker_events_universal script --

sudo tee /usr/local/bin/docker_events_universal.sh > /dev/null <<'EOF'
#!/bin/bash

set -euo pipefail

TARGET_IMAGE="ubuntu:24.04"
TARGET_NAME="clore-default-"
# TARGET_NAME="octa_idle_job"

SCREEN_NAME="miner"

START_CMD=""
ARGS=""

RESET_OC="false"

if [[ -z "$START_CMD" ]]; then
    echo "$(date): START_CMD empty — refusing to start miner"
    return
fi

# FUNCTIONS

start_miner() {
    if ! screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Starting $SCREEN_NAME..."
        screen -dmS "$SCREEN_NAME" bash -c "$START_CMD $ARGS"
        echo "Miner started in screen session: $SCREEN_NAME"
        echo "To view miner output: sudo screen -r $SCREEN_NAME"
    else
        echo "$(date): Miner already running in screen session: $SCREEN_NAME"
    fi
}

stop_miner() {
    if screen -list | grep -q "$SCREEN_NAME"; then
        echo "$(date): Stopping $SCREEN_NAME miner..."

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
    candidates=$(
        docker ps -a \
            --filter "ancestor=${TARGET_IMAGE}" \
            --format "{{.ID}} {{.Names}}"
    )

    match_id=""

    while read -r cid cname; do
        if [[ "$cname" == "$TARGET_NAME" ]]; then
            match_id="$cid"
            break
        fi

        if [[ "$cname" == ${TARGET_NAME}* ]]; then
            suffix="${cname#${TARGET_NAME}}"
            if [[ "$suffix" =~ ^[0-9]+$ ]]; then
                match_id="$cid"
                break
            fi
        fi
    done <<< "$candidates"

    if [[ -z "$match_id" ]]; then
        echo "no matching container treat as stopped"
        return 1
    fi

    status=$(docker inspect -f '{{.State.Status}}' "$match_id" 2>/dev/null)

    if [[ "$status" == "running" ]]; then
        return 0
    else
        echo "status=$status treat as stopped"
        return 1
    fi
}

# INITIAL CHECK

if check_target_container; then
    echo "$(date): Target container (${TARGET_IMAGE} name ${TARGET_NAME}) detected at startup"
    start_miner
else
    echo "$(date): Target container (${TARGET_IMAGE} name ${TARGET_NAME}) not found at startup"
    stop_miner
fi

# DOCKER EVENT LOOP

echo "$(date): Starting Docker event monitor..."

docker events \
    --format "{{.Type}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}" |
while read -r type action name image; do

    if [[ "$type" != "container" ]]; then
        echo "$(date): non-container event: Type: $type, Action: $action, Name: $name"
        continue
    fi

    echo "$(date): Container event detected - Action: $action, Name: $name, Image: $image"

    name_match=0

    if [[ "$name" == "$TARGET_NAME" ]]; then
        name_match=1
    elif [[ "$name" == ${TARGET_NAME}* ]]; then
        suffix="${name#${TARGET_NAME}}"
        if [[ "$suffix" =~ ^[0-9]+$ ]]; then
            name_match=1
        fi
    fi

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
                ;;
        esac
    fi
done
EOF

# -- write GPU service --

sudo tee /etc/systemd/system/docker_events_gpu.service > /dev/null <<'EOF'
[Unit]
Description=docker_events_gpu Watchdog
After=docker.service nvidia-persistenced.service
Requires=docker.service

[Service]
User=root
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
Restart=always
RestartSec=2
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable docker_events_gpu.service
sudo systemctl start docker_events_gpu.service

sudo journalctl -u docker_events_gpu.service -f

# -- gpu_reset not needed for clore when using oc profiles --
# -- leave commented out in service --

sudo tee /usr/local/bin/gpu_reset_poststop.sh > /dev/null <<'EOF'
#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

for i in {1..10}; do
    if nvidia-smi >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

echo "[GPU-RESET] Starting GPU reset sequence..."

for id in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
    echo "[GPU-RESET] Resetting GPU $id"

    nvidia-smi -i "$id" -rgc >/dev/null 2>&1
    nvidia-smi -i "$id" -rmc >/dev/null 2>&1

    default_pl=$(nvidia-smi -i "$id" \
        --query-gpu=power.default_limit \
        --format=csv,noheader,nounits)

    if [[ -n "$default_pl" ]]; then
        echo "[GPU-RESET] Setting GPU $id power limit → ${default_pl}W"
        nvidia-smi -i "$id" --power-limit="$default_pl" >/dev/null 2>&1
    else
        echo "[GPU-RESET] Skipping GPU $id (no default PL found)"
    fi
done

echo "[GPU-RESET] Complete."
EOF

sudo chmod +x /usr/local/bin/gpu_reset_poststop.sh
