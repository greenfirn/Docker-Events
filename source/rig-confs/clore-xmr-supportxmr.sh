tee /home/user/rig-cpu.conf > /dev/null <<'EOF'
TARGET_IMAGE 0 "ubuntu:24.04"
TARGET_NAME 0 "clore-default-"
RESET_OC 0 "false"
SCREEN_NAME 0 "cpu"
CUSTOM_MINER 0 ""
MINER 0 "xmrig"
ALGO 0 "rx/0"
POOL 0 "pool.supportxmr.com:9000"
WALLET 0 "***********************"
PASS 0 "%WORKER_NAME%"
ARGS 0 "-t %CPU_THREADS% --tls -k --randomx-1gb-pages --huge-pages"
EOF
sudo systemctl enable docker_events_cpu
sudo systemctl restart docker_events_cpu
sudo systemctl is-active docker_events_cpu
