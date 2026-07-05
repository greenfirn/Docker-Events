sudo tee /home/user/rig-gpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 ""
TARGET_NAME 0 ""
RESET_OC 0 "true"
APPLY_OC 0 "true"
SCREEN_NAME 0 "gpu"
CUSTOM_MINER 0 "/home/user/miners/keryx-miner/keryx-miner"
MINER 0 ""
ALGO 0 ""
POOL 0 ""
WALLET 0 ""
PASS 0 ""
ARGS 0 "--mining-address keryx:****************** --keryxd-address 10.20.0.105:22110"
EOF
sudo systemctl restart docker_events_gpu
sudo systemctl is-active docker_events_gpu
