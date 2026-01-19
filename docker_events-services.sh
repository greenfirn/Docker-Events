# -- write GPU service --

sudo tee /etc/systemd/system/docker_events_gpu.service > /dev/null <<'EOF'
[Unit]
Description=docker_events_gpu Watchdog
After=docker.service
After=nvidia-persistenced.service
Requires=docker.service

[Service]
User=root
#Environment="OC_FILE=/home/user/rig-gpu.conf"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_gpu.sh
ExecStart=/usr/local/bin/docker_events_gpu.sh
#ExecStopPost=/usr/local/bin/gpu_reset_poststop.sh
Restart=always
RestartSec=2
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

#========================================================================================================

# -- write CPU service --

sudo tee /etc/systemd/system/docker_events_cpu.service > /dev/null <<'EOF'
[Unit]
Description=docker_events_cpu Watchdog
After=docker.service
After=nvidia-persistenced.service
Requires=docker.service

[Service]
User=root
#Environment="OC_FILE=/home/user/rig-cpu.conf"
ExecStartPre=/bin/chmod +x /usr/local/bin/docker_events_cpu.sh
ExecStart=/usr/local/bin/docker_events_cpu.sh
Restart=always
RestartSec=2
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

#========================================================================================================

# let daemon know about changes
sudo systemctl daemon-reload

# enable so it starts on boot, start service
# sudo systemctl enable docker_events_gpu.service
# sudo systemctl start docker_events_gpu.service

# sudo systemctl enable docker_events_cpu.service
# sudo systemctl start docker_events_cpu.service

#========================================================================================================

# sudo systemctl stop docker_events_gpu.service
# sudo systemctl stop docker_events_cpu.service

# disable so it doesnt start on boot
# sudo systemctl disable docker_events_gpu.service
# sudo systemctl disable docker_events_cpu.service

# watch logs
# sudo journalctl -u docker_events_gpu.service -f
# sudo journalctl -u docker_events_cpu.service -f
