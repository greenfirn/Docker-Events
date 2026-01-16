# Check current states
cat /sys/class/drm/card0/device/pp_dpm_sclk
cat /sys/class/drm/card0/device/pp_dpm_mclk

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

echo "Done! Actual core speed will be ~1350MHz due to 90W power limit"

# Check if fan is in auto mode
cat /sys/class/drm/card0/device/hwmon/hwmon*/pwm1_enable
# 0 = no fan (off)
# 1 = manual mode
# 2 = automatic mode (default)




#!/bin/bash
echo "Resetting to defaults..."

# Auto control
echo "auto" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Remove power limit (set to card's max, ~135W for RX 6600 XT)
echo 135000000 | sudo tee /sys/class/drm/card0/device/hwmon/hwmon*/power1_cap

# Reset fan to auto (PWM 0 = auto)
# echo 0 | sudo tee /sys/class/drm/card0/device/hwmon/hwmon*/pwm1

echo "Reset complete"