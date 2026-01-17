sudo tee /usr/local/bin/gpu_apply_ocs.sh > /dev/null <<'EOF'
#!/bin/bash
# Save as set-amd-clocks.sh

echo "Setting AMD RX 6600 XT for mining..."

# Set manual control
echo "manual" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Set core to 1950MHz (will throttle with power limit)
echo "1" | sudo tee /sys/class/drm/card0/device/pp_dpm_sclk

# Set memory to 1000MHz
echo "3" | sudo tee /sys/class/drm/card0/device/pp_dpm_mclk

# Set power limit to 69W (this controls actual speed)
echo 69000000 | sudo tee /sys/class/drm/card0/device/hwmon/hwmon*/power1_cap

# Set fan speed 70 %
# echo 180 | sudo tee /sys/class/drm/card0/device/hwmon/hwmon*/pwm1

echo "Done! Actual core speed will be ~1350MHz due to 69W power limit"

# Check current states
cat /sys/class/drm/card0/device/pp_dpm_sclk
cat /sys/class/drm/card0/device/pp_dpm_mclk
rocm-smi
EOF

# make it executable
sudo chmod +x /usr/local/bin/gpu_apply_ocs.sh

sudo /usr/local/bin/gpu_apply_ocs.sh