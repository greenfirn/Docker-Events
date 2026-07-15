tee /home/user/rig-gpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 ""
TARGET_NAME 0 ""
RESET_OC 0 "true"
SCREEN_NAME 0 "gpu"
CUSTOM_MINER 0 ""
MINER 0 "wildrig"
ALGO 0 "pearlhash"
POOL 0 "stratum+tcp://pool.pearlhash.xyz:9000"
WALLET 0 "prl1*********************.%WORKER_NAME%"
PASS 0 "x"
ARGS 0 "--gpu-reset-oc --gpu-powerlimit 300 --gpu-core-clock 2490 --gpu-core-offset 325 --gpu-memory-clock 7001"
EOF
sudo systemctl restart docker_events_gpu
sudo systemctl is-active docker_events_gpu
