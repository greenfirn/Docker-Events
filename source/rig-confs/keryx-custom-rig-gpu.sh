tee /home/user/rig-gpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 ""
TARGET_NAME 0 ""
RESET_OC 0 "true"
APPLY_OC 0 "true"
SCREEN_NAME 0 "gpu"
CUSTOM_MINER_URL 0 "https://github.com/Keryx-Labs/keryx-miner/releases/download/v0.3.6-OPoI/keryx-miner-v0.3.6-OPoI-linux-gnu-amd64.zip"
CUSTOM_MINER 0 "keryx-miner"
MINER 0 ""
ALGO 0 ""
POOL 0 ""
WALLET 0 ""
PASS 0 ""
# add to cmd before first run or save escrow.key to new location and add to cmd... --escrow-key-file /home/user/miners/escrow.key
ARGS 0 "--mining-address keryx:****************** --keryxd-address 10.20.0.105:22110"
EOF

sudo systemctl restart docker_events_gpu
sudo systemctl is-active docker_events_gpu
