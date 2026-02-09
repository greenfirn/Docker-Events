# -- ** gpu_reset not used for clore when using oc profiles ** --
# -- leave commented out in service ... #ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh

# -- write gpu reset script --

sudo tee /usr/local/bin/gpu_reset_poststop.sh > /dev/null <<'EOF'
#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "[GPU-RESET] Starting GPU reset sequence..."

# Check for power limit argument
POWER_LIMIT=""
if [ $# -eq 1 ]; then
    if [[ $1 =~ ^[0-9]+$ ]] && [ $1 -gt 0 ]; then
        POWER_LIMIT=$1
        echo "[GPU-RESET] Power limit specified: ${POWER_LIMIT}W"
    else
        echo "[GPU-RESET] Warning: Invalid power limit '$1'. Must be integer > 0. Using default."
    fi
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to reset NVIDIA GPUs
reset_nvidia_gpus() {
    echo "[GPU-RESET] Detected NVIDIA GPU(s)"
    
    # Wait for NVIDIA driver to become available
    for i in {1..10}; do
        if nvidia-smi >/dev/null 2>&1; then break; fi
        sleep 1
    done
    
    for id in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
        echo "[GPU-RESET] Resetting NVIDIA GPU $id"
        
        # Reset clocks
        nvidia-smi -i "$id" -rgc >/dev/null 2>&1
        nvidia-smi -i "$id" -rmc >/dev/null 2>&1
        
        # Set power limit based on user input or default
        if [ -n "$POWER_LIMIT" ]; then
            echo "[GPU-RESET] Setting NVIDIA GPU $id power limit → ${POWER_LIMIT}W (user specified)"
            nvidia-smi -i "$id" --power-limit="$POWER_LIMIT" >/dev/null 2>&1
        else
            # Query default safe power limit
            default_pl=$(nvidia-smi -i "$id" --query-gpu=power.default_limit --format=csv,noheader,nounits 2>/dev/null)
            
            if [ -n "$default_pl" ]; then
                echo "[GPU-RESET] Setting NVIDIA GPU $id power limit → ${default_pl}W (default)"
                nvidia-smi -i "$id" --power-limit="$default_pl" >/dev/null 2>&1
            else
                echo "[GPU-RESET] Skipping NVIDIA GPU $id power limit (no default PL found)"
            fi
        fi
    done
}

# Main detection
if command_exists "nvidia-smi" && nvidia-smi >/dev/null 2>&1; then
    reset_nvidia_gpus
else
    echo "[GPU-RESET] No GPU detected"
fi

echo "[GPU-RESET] Complete."
EOF

# Make it executable
sudo chmod +x /usr/local/bin/gpu_reset_poststop.sh

# test proper power limit etc is applied
sudo /usr/local/bin/gpu_reset_poststop.sh