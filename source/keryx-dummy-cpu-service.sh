sudo tee /etc/systemd/system/docker_events_cpu.service > /dev/null <<'EOF'
[Unit]
Description=Keryx Miner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/user/miners/keryx-miner/current
Environment="LOG_FILE=/tmp/gpu_miner.log"
Environment="MAX_LOG_BYTES=10485760"
Environment="LOG_CHECK_INTERVAL=60"
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
#ExecStartPre=/usr/local/bin/gpu_apply_ocs.sh
ExecStart=/bin/bash -c '\
set -o pipefail; \
rm -f "$LOG_FILE"; \
( while true; do \
    sleep "$LOG_CHECK_INTERVAL"; \
    sz=$(stat -c%%s "$LOG_FILE" 2>/dev/null || echo 0); \
    if [ "$sz" -gt "$MAX_LOG_BYTES" ]; then \
        tmp="$LOG_FILE.tmp"; \
        tail -c "$MAX_LOG_BYTES" "$LOG_FILE" > "$tmp" 2>/dev/null && cat "$tmp" > "$LOG_FILE" && rm -f "$tmp"; \
    fi; \
  done ) & \
/home/user/miners/keryx-miner/current/keryx-miner --mining-address keryx:**************** --keryxd-address 127.0.0.1:22110 2>&1 | tee -a "$LOG_FILE"'
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
#LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl restart docker_events_cpu.service

sudo journalctl -u docker_events_cpu.service -f
