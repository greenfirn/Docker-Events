sudo tee /usr/local/bin/gpu_reset_poststop.sh > /dev/null <<'EOF'
#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "[GPU-RESET] Starting GPU reset sequence..."

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
        
        # Query default safe power limit
        default_pl=$(nvidia-smi -i "$id" --query-gpu=power.default_limit --format=csv,noheader,nounits 2>/dev/null)
        
        if [ -n "$default_pl" ]; then
            echo "[GPU-RESET] Setting NVIDIA GPU $id power limit → ${default_pl}W"
            nvidia-smi -i "$id" --power-limit="$default_pl" >/dev/null 2>&1
        else
            echo "[GPU-RESET] Skipping NVIDIA GPU $id (no default PL found)"
        fi
    done
}

# Function to reset AMD GPUs to COMPLETE defaults (no manual settings)
reset_amd_gpus() {
    echo "[GPU-RESET] Detected AMD GPU(s)"
    
    # Process only actual GPU cards
    for card in /sys/class/drm/card[0-9]*/device; do
        if [ ! -d "$card" ]; then
            continue
        fi
        
        # Get card number
        card_name=$(basename "$(dirname "$card")")
        if [[ ! "$card_name" =~ ^card[0-9]+$ ]]; then
            continue
        fi
        
        card_num=$(echo "$card_name" | sed 's/card//')
        echo "[GPU-RESET] Processing GPU $card_num"
        
        # 1. RESET POWER LIMIT TO DEFAULT
        echo "[GPU-RESET] 1. Resetting power limit..."
        
        # Find hwmon directory
        hwmon_dir=$(ls -d "$card/hwmon/hwmon"* 2>/dev/null | head -1)
        
        if [ -d "$hwmon_dir" ] && [ -f "$hwmon_dir/power1_cap_default" ]; then
            default_val=$(cat "$hwmon_dir/power1_cap_default" 2>/dev/null)
            current_val=$(cat "$hwmon_dir/power1_cap" 2>/dev/null)
            
            if [ -n "$default_val" ] && [ "$default_val" != "0" ]; then
                default_w=$((default_val / 1000000))
                current_w=$((current_val / 1000000))
                
                echo "[GPU-RESET]   Current: ${current_w}W, Default: ${default_w}W"
                
                if [ "$current_val" != "$default_val" ]; then
                    echo "$default_val" | sudo tee "$hwmon_dir/power1_cap" >/dev/null 2>&1
                    new_val=$(cat "$hwmon_dir/power1_cap" 2>/dev/null)
                    if [ "$new_val" = "$default_val" ]; then
                        new_w=$((new_val / 1000000))
                        echo "[GPU-RESET]   ✓ Power limit set to ${new_w}W"
                    fi
                else
                    echo "[GPU-RESET]   ✓ Already at default ${current_w}W"
                fi
            fi
        fi
        
        # 2. RESET POWER PROFILE TO AUTO (THIS REMOVES MANUAL CLOCK SETTINGS!)
        echo "[GPU-RESET] 2. Resetting power profile to auto..."
        if [ -f "$card/power_dpm_force_performance_level" ]; then
            echo "auto" | sudo tee "$card/power_dpm_force_performance_level" >/dev/null 2>&1
            echo "[GPU-RESET]   ✓ Set to auto (removes manual clock settings)"
            
            # When set to "auto", the GPU will automatically manage:
            # - pp_dpm_sclk (core clock)
            # - pp_dpm_mclk (memory clock) 
            # - and other power states
        fi
        
        # 3. RESET OVERDRIVE CLOCKS
        echo "[GPU-RESET] 3. Resetting overdrive clocks..."
        if [ -f "$card/pp_od_clk_voltage" ]; then
            echo "r" | sudo tee "$card/pp_od_clk_voltage" >/dev/null 2>&1
            echo "c" | sudo tee "$card/pp_od_clk_voltage" >/dev/null 2>&1
            echo "[GPU-RESET]   ✓ Reset OD clocks"
        fi
        
        # 4. RESET ANY MANUAL DPM STATES (optional cleanup)
        echo "[GPU-RESET] 4. Cleaning up manual DPM states..."
        # Just setting power_dpm_force_performance_level to "auto" should be enough
        # But we can also check the current state
        if [ -f "$card/pp_dpm_sclk" ]; then
            echo "[GPU-RESET]   SCLK states (will be auto-managed):"
            cat "$card/pp_dpm_sclk" 2>/dev/null | head -5
        fi
        
        if [ -f "$card/pp_dpm_mclk" ]; then
            echo "[GPU-RESET]   MCLK states (will be auto-managed):"
            cat "$card/pp_dpm_mclk" 2>/dev/null | head -5
        fi
        
        # 5. USE ROCM-SMI FOR ADDITIONAL RESETS
        if command_exists "rocm-smi"; then
            echo "[GPU-RESET] 5. Using rocm-smi..."
            rocm-smi -d "$card_num" --resetclocks >/dev/null 2>&1
            rocm-smi -d "$card_num" --resetfans >/dev/null 2>&1
            rocm-smi -d "$card_num" --setfanauto >/dev/null 2>&1
            rocm-smi -d "$card_num" --setperflevel auto >/dev/null 2>&1
            echo "[GPU-RESET]   ✓ Applied rocm-smi resets"
        fi
        
        echo "[GPU-RESET] GPU $card_num reset complete"
        echo ""
    done
    
    echo "[GPU-RESET] AMD GPU reset complete"
}

# Main detection
if command_exists "nvidia-smi" && nvidia-smi >/dev/null 2>&1; then
    reset_nvidia_gpus
elif ls -d /sys/class/drm/card[0-9]* >/dev/null 2>&1; then
    reset_amd_gpus
elif command_exists "rocm-smi" && rocm-smi >/dev/null 2>&1; then
    reset_amd_gpus
else
    echo "[GPU-RESET] No GPU detected"
fi

echo "[GPU-RESET] Complete."
EOF
# Make it executable
sudo chmod +x /usr/local/bin/gpu_reset_poststop.sh