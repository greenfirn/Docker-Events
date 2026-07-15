tee /home/user/rig-gpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 ""
TARGET_NAME 0 ""
RESET_OC 0 "true"
SCREEN_NAME 0 "gpu"
CUSTOM_MINER 0 ""
MINER 0 "srbminer"
ALGO 0 "pearlhash"
POOL 0 "ca.pearl.herominers.com:1200, us2.pearl.herominers.com:1200"
WALLET 0 "prl1********************.%WORKER_NAME%"
PASS 0 "x"
ARGS 0 "--tls false --disable-cpu --gpu-id 0 --gpu-cclock0 2490 --gpu-coffset0 300 --gpu-mclock0 7001 --gpu-plimit0 300"
EOF
sudo systemctl restart docker_events_gpu
sudo systemctl is-active docker_events_gpu
