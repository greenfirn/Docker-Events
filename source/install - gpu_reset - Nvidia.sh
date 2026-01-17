
# -- ** gpu_reset not used for clore when using oc profiles ** --
# -- leave commented out in service ... #ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh

# -- write gpu reset script --

sudo tee /usr/local/bin/gpu_reset_poststop.sh > /dev/null <<'EOF'
#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Wait for NVIDIA driver to become available
for i in {1..10}; do
    if nvidia-smi >/dev/null 2>&1; then break; fi
    sleep 1
done

echo "[GPU-RESET] Starting GPU reset sequence..."

for id in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
    echo "[GPU-RESET] Resetting GPU $id"

    # Reset clocks
    nvidia-smi -i "$id" -rgc >/dev/null 2>&1
    nvidia-smi -i "$id" -rmc >/dev/null 2>&1

    # Query default safe power limit (NOT the fuse limit!)
    default_pl=$(nvidia-smi -i "$id" --query-gpu=power.default_limit --format=csv,noheader,nounits)

    if [ -n "$default_pl" ]; then
        echo "[GPU-RESET] Setting GPU $id power limit → ${default_pl}W"
        nvidia-smi -i "$id" --power-limit="$default_pl" >/dev/null 2>&1
    else
        echo "[GPU-RESET] Skipping GPU $id (no default PL found)"
    fi
done
echo "[GPU-RESET] Complete."
EOF

# make executable
sudo chmod +x /usr/local/bin/gpu_reset_poststop.sh
