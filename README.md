# Docker Events

> ⚠️ **Use extreme caution with any custom scripts — you're risking your host or account being banned.** Test thoroughly before relying on this.

---

## What it can do

- Watch Docker/Podman container events on a rig and automatically starts/stops mining or applies overclocks based on container state — Clore, Octaspace, Nosana (Podman), VastAI (CPU mining, testing)
- more recent files in source, easiest to use 'no-container-docker_events_monitor'
- Starts/stops mining when no containers are running / when an active idle container appears or disappears
- Applies or resets GPU overclocks based on container state
- for testing: start, stop, or pause an idle job on platform, watch logs etc to confirm expected behavior
- Includes `-retry-on-failure` variants that loop on Docker events in case of disconnects/failures

See the `source/` folder for the full package: install scripts, miners, and rig configs.

---

## Platform-specific monitors

| Platform | Script | `TARGET_NAME` |
|---|---|---|
| VastAI (CPU mining only, testing) | `source/no-container-docker_events_monitor-vast.sh` | `vast` |
| Nosana / Podman (testing) | `nosana_monitor-1.sh`, `source/podman_events_monitor.sh` | `podman` |

> VastAI Note: a short server test seems to run around benchmark time — likely the platform confirming host specs.

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

## Credits

Some portions of this project were developed with assistance from ChatGPT and DeepSeek.
