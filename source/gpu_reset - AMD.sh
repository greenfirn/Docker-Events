# -- ** gpu_reset not used for clore when using oc profiles ** --
# -- leave commented out in service ... #ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh

# -- write gpu reset script --

sudo tee /usr/local/bin/gpu_reset_poststop.sh > /dev/null <<'EOF'
#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "[GPU-RESET] Starting GPU reset sequence..."

# Check if power limit was passed as command line argument
if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    CMD_POWER_LIMIT="$1"
    echo "[GPU-RESET] Using command line power limit: ${CMD_POWER_LIMIT}W"
    USE_SPECIFIED_LIMIT=true
    TARGET_POWER="$CMD_POWER_LIMIT"
else
    USE_SPECIFIED_LIMIT=false
    echo "[GPU-RESET] No power limit specified - will use GPU default values"
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to reset AMD GPUs
reset_amd_gpus() {
    local use_custom_power="$1"
    local target_power="$2"
    
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
        
        # 1. SET/RESET POWER LIMIT
        echo "[GPU-RESET] 1. Configuring power limit..."
        
        # Find hwmon directory
        hwmon_dir=$(ls -d "$card/hwmon/hwmon"* 2>/dev/null | head -1)
        
        if [ -d "$hwmon_dir" ] && [ -f "$hwmon_dir/power1_cap" ]; then
            if [ "$use_custom_power" = true ]; then
                # Use specified power limit
                target_microwatts=$((target_power * 1000000))
                echo "[GPU-RESET]   Setting to specified limit: ${target_power}W"
                
                # Set to target value
                echo "$target_microwatts" | sudo tee "$hwmon_dir/power1_cap" >/dev/null 2>&1
                new_val=$(cat "$hwmon_dir/power1_cap" 2>/dev/null)
                
                if [ -n "$new_val" ] && [ "$new_val" != "0" ]; then
                    new_w=$((new_val / 1000000))
                    echo "[GPU-RESET]   ✓ Power limit set to ${new_w}W"
                else
                    echo "[GPU-RESET]   ⚠ Could not verify power limit setting"
                fi
            else
                # Use GPU's default power limit (your original logic)
                if [ -f "$hwmon_dir/power1_cap_default" ]; then
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
                                echo "[GPU-RESET]   ✓ Power limit reset to default ${new_w}W"
                            fi
                        else
                            echo "[GPU-RESET]   ✓ Already at default ${current_w}W"
                        fi
                    else
                        echo "[GPU-RESET]   ⚠ Could not read default power limit"
                    fi
                else
                    echo "[GPU-RESET]   ⚠ No default power limit file found"
                fi
            fi
        else
            echo "[GPU-RESET]   ⚠ No power cap interface found"
        fi
        
        # 2. RESET POWER PROFILE TO AUTO
        echo "[GPU-RESET] 2. Resetting power profile to auto..."
        if [ -f "$card/power_dpm_force_performance_level" ]; then
            echo "auto" | sudo tee "$card/power_dpm_force_performance_level" >/dev/null 2>&1
            echo "[GPU-RESET]   ✓ Set to auto (removes manual clock settings)"
        fi
        
        # 3. RESET OVERDRIVE CLOCKS
        echo "[GPU-RESET] 3. Resetting overdrive clocks..."
        if [ -f "$card/pp_od_clk_voltage" ]; then
            echo "r" | sudo tee "$card/pp_od_clk_voltage" >/dev/null 2>&1
            echo "c" | sudo tee "$card/pp_od_clk_voltage" >/dev/null 2>&1
            echo "[GPU-RESET]   ✓ Reset OD clocks"
        fi
        
        # 4. USE ROCM-SMI FOR ADDITIONAL RESETS
        if command_exists "rocm-smi"; then
            echo "[GPU-RESET] 4. Using rocm-smi..."
            rocm-smi -d "$card_num" --resetclocks >/dev/null 2>&1
            rocm-smi -d "$card_num" --resetfans >/dev/null 2>&1
            rocm-smi -d "$card_num" --setfanauto >/dev/null 2>&1
            rocm-smi -d "$card_num" --setperflevel auto >/dev/null 2>&1
            echo "[GPU-RESET]   ✓ Applied rocm-smi resets"
        fi
        
        echo "[GPU-RESET] GPU $card_num reset complete"
        echo ""
    done
    
    if [ "$use_custom_power" = true ]; then
        echo "[GPU-RESET] AMD GPU reset complete with ${target_power}W power limit"
    else
        echo "[GPU-RESET] AMD GPU reset complete (using GPU defaults)"
    fi
}

# Main execution

if ls -d /sys/class/drm/card[0-9]* >/dev/null 2>&1; then
    reset_amd_gpus "$USE_SPECIFIED_LIMIT" "$TARGET_POWER"
elif command_exists "rocm-smi" && rocm-smi >/dev/null 2>&1; then
    reset_amd_gpus "$USE_SPECIFIED_LIMIT" "$TARGET_POWER"
else
    echo "[GPU-RESET] No GPU detected"
fi

echo "[GPU-RESET] Complete."
if command_exists "rocm-smi"; then
    rocm-smi
fi
EOF

# Make executable
sudo chmod +x /usr/local/bin/gpu_reset_poststop.sh

# Make it executable
sudo chmod +x /usr/local/bin/gpu_reset_poststop.sh

# test proper power limit etc is applied
sudo /usr/local/bin/gpu_reset_poststop.sh
