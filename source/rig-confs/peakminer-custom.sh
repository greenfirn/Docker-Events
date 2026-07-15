tee /home/user/rig-gpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 "ubuntu:24.04"
TARGET_NAME 0 ""
RESET_OC 0 "true"
APPLY_OC 0 "false"
SCREEN_NAME 0 "gpu"
CUSTOM_MINER_URL 0 "https://github.com/peakminer/peakminer/releases/download/v2.0.0/peakminer-2.0.0.tar.gz"
CUSTOM_MINER 0 "peakminer"
# xmrig, wildrig, bzminer, srbminer, rigel, lolminer, onezerominer, gminer, teamredminer, trex
MINER 0 ""
ALGO 0 ""
POOL 0 ""
WALLET 0 ""
PASS 0 "x"
ARGS 0 "--api-port 4068 --coin pearl --url ca.pearl.herominers.com:1200 --user prl1*********************.%WORKER_NAME% --gpu-power 300 --gpu-lcore 2475 --gpu-core 375 --gpu-lmem 7001"
EOF
sudo systemctl restart docker_events_gpu
