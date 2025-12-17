docker_events_universal Script – Installation & Layout Guide

This document describes how to install and operate the modularized
docker_events_universal script used by RigCloud to automatically start and stop
CPU/GPU miners based on Docker container lifecycle events.

======================================================================

OVERVIEW

The script monitors Docker events and:
- Detects when a target container starts or stops
- Starts the appropriate miner inside a screen session
- Stops the miner cleanly when the container exits
- Optionally resets GPU clocks after stop

The logic is split into a main script plus reusable library files.

======================================================================

DIRECTORY LAYOUT

The following layout is REQUIRED.

source/
├── docker_events_universal.sh
├── lib/
│   ├── 00-get_rig_conf.sh
│   ├── 01-miner_install.sh
│   ├── 02-load_configs.sh
│   ├── 03-cpu_threads.sh
│   └── 04-algo_config.sh

======================================================================

FILE RESPONSIBILITIES

docker_events_universal.sh
--------------------------
Main entrypoint.
- Determines script location
- Sources all lib files in strict order
- Runs Docker event loop
- Starts/stops miners using screen

lib/00-get_rig_conf.sh
---------------------
- Provides get_rig_conf() helper
- Reads values from rig.conf
- Supports GPU-specific and ALL entries

lib/01-miner_install.sh
-----------------------
- Installs miners based on versions in rig.conf
- Maintains /current symlinks
- Generates miner_paths.env

lib/02-load_configs.sh
----------------------
- Loads miner selection and runtime config
- Resolves:
  TARGET_IMAGE
  TARGET_NAME
  MINER_NAME
  POOL / WALLET / PASS
  SCREEN_NAME
- Builds START_CMD

lib/03-cpu_threads.sh
---------------------
- Calculates TOTAL_THREADS and CPU_THREADS
- Applies XMRig affinity logic
- Replaces %CPU_THREADS% placeholders

lib/04-algo_config.sh
---------------------
- Algorithm-specific logic (e.g. warthog)
- Replaces %WARTHOG_TARGET% placeholders

======================================================================

CONFIGURATION FILE

Default config location:
  /home/user/rig-cpu.conf

Example entries:

TARGET_IMAGE ALL cloreai/jupyter:ubuntu24.04-v2
TARGET_NAME  ALL clore-default-
MINER        ALL bzminer
ALGO         ALL warthog
POOL         ALL stratum+ssl://example.pool:1234
WALLET       ALL WALLET_ADDRESS
PASS         ALL %WORKER_NAME%
SCREEN_NAME  ALL gpu-miner
RESET_OC     ALL true

======================================================================

INSTALLATION STEPS

1) Create install directory
---------------------------
sudo mkdir -p /usr/local/bin/rigcloud/lib

2) Copy scripts
---------------
sudo cp docker_events_universal.sh /usr/local/bin/rigcloud/
sudo cp lib/*.sh /usr/local/bin/rigcloud/lib/

3) Make executable
------------------
sudo chmod +x /usr/local/bin/rigcloud/docker_events_universal.sh
sudo chmod +x /usr/local/bin/rigcloud/lib/*.sh

4) Test manually
----------------
sudo /usr/local/bin/rigcloud/docker_events_universal.sh

You should see Docker event output and miner start/stop messages.

======================================================================

SYSTEMD SERVICE SETUP

Example service file:

/etc/systemd/system/docker_events_gpu.service

[Unit]
Description=RigCloud Docker Event Monitor (GPU)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/rigcloud/docker_events_universal.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target

Enable and start:

sudo systemctl daemon-reload
sudo systemctl enable docker_events_gpu.service
sudo systemctl start docker_events_gpu.service

======================================================================

LOGGING & DEBUGGING

Follow logs:
  sudo journalctl -u docker_events_gpu.service -f

Check miner screens:
  screen -ls
  screen -r <screen_name>

======================================================================

SAFETY NOTES

- Script never kills Docker containers
- Miner is isolated in screen session
- GPU reset is optional and controlled via rig.conf
- Safe under Docker restarts and container crashes

======================================================================

INTENDED USE

- RigCloud-managed GPU/CPU rigs
- Clore / OctaSpace / Vast.ai hosts
- Automated mining + workload switching
