# stop old services
sudo systemctl stop docker_events_gpu.service
sudo systemctl stop docker_events_cpu.service

# disable so it doesnt run on boot
sudo systemctl disable docker_events_gpu.service
sudo systemctl disable docker_events_cpu.service

# -- write GPU service --

sudo tee /etc/systemd/system/docker-events-gpu.service > /dev/null <<'EOF'
[Unit]
Description=Docker Events GPU Miner Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Environment="OC_FILE=/home/user/rig-gpu.conf"
Environment="MINER_CONF=/home/user/miner.conf"
Environment="API_CONF=/home/user/api.conf"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
Restart=always
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal

# Allow up to 10 seconds for graceful shutdown
TimeoutStopSec=10
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF


# -- write CPU service --

sudo tee /etc/systemd/system/docker-events-cpu.service > /dev/null <<'EOF'
[Unit]
Description=Docker Events CPU Miner Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Environment="OC_FILE=/home/user/rig-cpu.conf"
Environment="MINER_CONF=/home/user/miner.conf"
Environment="API_CONF=/home/user/api.conf"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_universal.sh
ExecStart=/usr/local/bin/docker_events_universal.sh
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
Restart=always
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal

# Allow up to 10 seconds for graceful shutdown
TimeoutStopSec=10
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

#========================================================================================================
#========================================================================================================

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable docker-events-gpu.service
sudo systemctl enable docker-events-cpu.service

# Start/Stop Service
sudo systemctl start docker-events-gpu.service
sudo systemctl stop docker-events-gpu.service

sudo systemctl start docker-events-cpu.service
sudo systemctl stop docker-events-cpu.service

# check status
sudo systemctl status docker-events-gpu.service
sudo systemctl status docker-events-cpu.service

# follow logs
sudo journalctl -u docker-events-gpu.service -f
sudo journalctl -u docker-events-cpu.service -f

# disable so it doesnt start on boot
sudo systemctl disable docker-events-gpu.service
sudo systemctl disable docker-events-cpu.service