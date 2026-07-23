# Docker Events

> ⚠️ **Use extreme caution with any custom scripts — you're risking your host or account being banned.** Test thoroughly before relying on this... not a good option for VastAI (CPU only) ... keep in mind power limit while idle mining will be what is shown in marketplace, so use locked core to limit power, Clore uses oc profiles that can't be over writen so not best if switching between mining very different coins

---

## Important

- scripts/services assume path '/home/user' exists

- sudo mkdir -p /home/user

## Notes

-- See `source` for latest examples and the full package: install scripts, miners, and rig configs. --

-- 'source/no-container-docker_events_monitor--LATEST...' is most recent updated, others may not work as is --

-- naming/layout may have changed for clore, nosana, etc --

-- oc reset/apply using 'nvidia-smi' may not be reliable under all situations... see 'source/py-nvtool/py-nvtool.txt' for nvtool oc control --

## Updates

- [Watchdog](source/watchdog), runs when no docker containers found, not tested...
- custom miner example '[source/peakminer-custom-gpu.sh](https://github.com/greenfirn/Docker-Events/blob/main/source/peakminer-custom-gpu.sh)'
- may need 'sudo apt install unzip' for custom miner zip archieves

## What the scripts can do

- Watch Docker/Podman container events on a rig and automatically start/stop mining and/or apply overclocks based on container state — Clore, Octaspace, Nosana (Podman), VastAI (CPU mining only, testing)
- more recent files in source, easiest to use 'no-container-docker_events_monitor'
- Start/stop mining when no containers are running / when an active idle container appears or disappears
- Apply or reset GPU overclocks based on container state
- for testing: start, stop, or pause an idle job on platform, watch logs etc to confirm expected behavior
- Includes `-retry-on-failure` in most examples that loop on Docker events in case of disconnects/failures

---

## Platform-specific monitors

| Platform | Script | `TARGET_NAME` |
|---|---|---|
| VastAI (CPU mining only, testing) | `source/no-container-docker_events_monitor-vast.sh` | `vast` |
| Nosana / Podman (testing) | `nosana_monitor-1.sh`, `source/podman_events_monitor.sh` | `podman` |

> VastAI Note: gpu idle mining not possible using this method, will interfere with benchmarking... a short server test seems to run around benchmark time — likely the platform confirming host specs.

For Podman idle detection, keep `PODMAN_IDLE_CONFIRM_LOOPS` and `IDLE_CONFIRMATION_THRESHOLD` at **4 or higher** to safely cover the gap between container load/unload.

---

## Useful commands

```bash
# Show currently running containers/images
sudo docker ps

# Follow live logs
sudo journalctl -u docker_events_gpu.service -f

# Show more log history
sudo journalctl -u docker_events_gpu.service -e
# (Ctrl+C to exit logs)

# GPU monitoring
sudo apt install -y nvtop   # NVIDIA
rocm-smi                    # AMD
```

---

## Development Notes

Built with assistance from ChatGPT, DeepSeek, Claude ai

---

## Support

Donations are appreciated:

MetaMask supported chains (ETH/Octaspace/Clore)
<img src="https://assets.coingecko.com/coins/images/279/standard/ethereum.png?1696501628" width="20" height="20" /> <img src="https://raw.githubusercontent.com/octaspace/logos/main/logo.svg" width="16" height="16" /> <img src="https://assets.coingecko.com/coins/images/30959/standard/CLORE_Logo_200x200_PNG.png?1696529798" width="16" height="16" />

`0xe65b5d7B7D43D77eF585CCF4a675832d0d23f806`
