tee /home/user/rig-gpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 "ubuntu:24.04"
TARGET_NAME 0 ""
RESET_OC 0 "false"
APPLY_OC 0 "false"
SCREEN_NAME 0 "gpu"
CUSTOM_MINER_URL 0 ""
CUSTOM_MINER 0 ""
# xmrig, wildrig, bzminer, srbminer, rigel, lolminer, onezerominer, gminer, teamredminer, trex
MINER 0 ""
ALGO 0 ""
POOL 0 ""
WALLET 0 ".%WORKER_NAME%"
PASS 0 "x"
ARGS 0 ""
EOF
sudo systemctl restart docker_events_gpu
