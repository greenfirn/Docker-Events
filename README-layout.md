# RigCloud File Layout

RigCloud's scripts currently hardcode every path under `/home/user/`, regardless of what the rig's actual installed username is. That works as long as a `/home/user/` directory (real account or not) exists on every rig, but it's not the standard Linux layout. This doc lays out where things should live if/when we move to the FHS-standard locations instead.

## Current vs recommended

| Category | Current | Recommended | Purpose |
|---|---|---|---|
| Config files | `/home/user/*.conf` (`rig-gpu.conf`, `rig-cpu.conf`, `miner.conf`, `api.conf`, `rigcloud-watchdog.conf`, `rigcloud-agent.conf`) | `/etc/rigcloud/` | Host-specific config — always root-readable, no dependency on any account existing |
| Scripts | `/home/user/rigcloud_cmd.sh` (most others already live in `/usr/local/bin/`) | `/usr/local/bin/` | Locally-installed executables |
| Miner installs | `/home/user/miners/` (e.g. `keryx-miner/`) | `/opt/rigcloud/miners/` | Self-contained third-party software packages |
| Stats DB | `/home/user/rigcloud_stats.db` | `/var/lib/rigcloud/` | Persistent on-disk service state |
| PID files | `/tmp/${SCREEN_NAME}_miner.pid` | `/run/rigcloud/` | Runtime files (tmpfs, cleared on boot — more idiomatic than `/tmp`, though `/tmp` isn't wrong) |

## Why this matters

Every RigCloud script — the agent, telemetry collector, watchdog, `rigcloud_cmd.sh` dispatcher, `docker_events_universal.sh`, and the miner systemd units — reads and writes these paths as literal strings. None of them derive the path from `$HOME`, `~`, or `whoami`. That means a rig with a different installed username has two options today:

1. Add a Linux account literally named `user` (`sudo adduser user`), or
2. Just create the directory (`sudo mkdir -p /home/user`) without a real account, since almost everything runs as `User=root` in its systemd unit — root doesn't care who nominally owns the path.

Moving to the FHS locations above sidesteps this entirely: `/etc`, `/opt`, `/var`, and `/run` aren't tied to any user's home directory, so no synthetic account or workaround directory is ever needed on a new rig.

## Migration scope

Moving to this layout touches every script currently hardcoding `/home/user/`:

- `rigcloud_agent.py` / `rigcloud_agent_win.py` (agent + config path)
- `rigcloud_telemetry.py` / `rigcloud_telemetry-win.py` (conf lookups)
- `rigcloud_watchdog.py` (`--conf` default)
- `rigcloud_cmd.sh` (dispatcher script path + sudoers entry)
- `docker_events_universal.sh` (`OC_FILE`, `MINER_CONF`, `API_CONF` defaults)
- `keryx-miner.service` and other miner systemd units (`WorkingDirectory`, `ExecStart`)

Not yet started — this is a proposal to review before touching any of the above.
