sudo tee /usr/local/bin/rigcloud_watchdog.py > /dev/null <<'EOF'
#!/usr/bin/env python3
"""
rigcloud_watchdog.py - Watches GPU power draw and mining hashrate, and
restarts the corresponding docker_events_{gpu,cpu}.service if a miner
looks dead (hashrate/watts below its configured threshold for too long).

Only backs off while a docker container is actually running.
docker_events_universal.sh stops the local miner whenever a docker
workload takes over the GPU/CPU, and its wrapper service stays "active"
throughout that handoff - so a dropped hashrate in that state is
expected, not a failure. The watchdog checks `docker ps -q` itself (same
as docker_events_universal.sh's own any_container_running()) and skips
all checks entirely while containers are running. If Docker itself isn't
installed/reachable on this rig, that's treated the same as "no
containers running" - normal hashrate/watts checks still apply.

This deliberately reuses rigcloud_telemetry.py (the same collector the
dashboard agent already relies on) instead of re-implementing GPU/miner
parsing here, so "what the watchdog sees" always matches "what the
dashboard sees".

Deployed twice, once per mode, by rigcloud_watchdog.sh:
  rigcloud_watchdog_gpu.service  --mode gpu --service docker_events_gpu.service
  rigcloud_watchdog_cpu.service  --mode cpu --service docker_events_cpu.service
"""
import argparse
import subprocess
import sys
import time
from datetime import datetime

sys.path.insert(0, "/usr/local/bin")
import rigcloud_telemetry as telemetry


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[Watchdog] {ts} {msg}", flush=True)


# ================================================================
# CONFIG - per-algo thresholds
# ================================================================
def load_watchdog_conf(path):
    """Loads ALGO,MIN_HASHRATE_HS,MIN_WATTS_TOTAL,GRACE_CHECKS,COOLDOWN_SECONDS
    rows into a dict keyed by lowercased algo name. Always guarantees a
    'default' entry exists, falling back to hardcoded defaults if the conf
    is missing/unreadable/has no DEFAULT row of its own."""
    thresholds = {}

    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = [p.strip() for p in line.split(",")]
                if len(parts) != 5:
                    log(f"[conf] Ignoring malformed line (expected 5 fields): {line!r}")
                    continue
                algo, min_hr, min_w, grace, cooldown = parts
                try:
                    thresholds[algo.strip().lower()] = {
                        "min_hashrate_hs": float(min_hr),
                        "min_watts_total": float(min_w),
                        "grace_checks": max(1, int(grace)),
                        "cooldown_seconds": max(0, int(cooldown)),
                    }
                except ValueError:
                    log(f"[conf] Ignoring line with non-numeric fields: {line!r}")
    except Exception as e:
        log(f"[conf] Error reading {path}: {e}")

    if "default" not in thresholds:
        log("[conf] No DEFAULT row found - using built-in fallback (min_hashrate_hs=1, min_watts_total=20, grace=3, cooldown=600s)")
        thresholds["default"] = {
            "min_hashrate_hs": 1,
            "min_watts_total": 20,
            "grace_checks": 3,
            "cooldown_seconds": 600,
        }

    return thresholds


def thresholds_for(conf, algo_name):
    return conf.get((algo_name or "").strip().lower(), conf["default"])


# ================================================================
# TELEMETRY AGGREGATION (reuses rigcloud_telemetry's own collectors)
# ================================================================
def algo_hashrate_for_mode(entry, mode):
    """A single miner's algorithm entry can carry mode-specific hashrate
    fields (cpu_hashrate_hs / gpu_hashrate_hs) for combined CPU+GPU miners
    like SRBMiner - prefer the mode-specific field when present, otherwise
    fall back to the plain hashrate_hs field most single-mode miners use."""
    field = "cpu_hashrate_hs" if mode == "cpu" else "gpu_hashrate_hs"
    val = entry.get(field)
    if val is None:
        val = entry.get("hashrate_hs")
    try:
        return float(val) if val is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


def collect_snapshot(mode):
    """Returns (total_watts, {algo_name: combined_hashrate_hs}) for the
    current telemetry snapshot. total_watts is 0 for --mode cpu (power
    draw is a GPU-only concept here)."""
    stats = telemetry.collect_full_stats()

    total_watts = 0.0
    if mode == "gpu":
        for gpu in stats.get("gpus", []) or []:
            try:
                total_watts += float(gpu.get("power_watts") or 0)
            except (TypeError, ValueError):
                pass

    algo_totals = {}
    for key, val in stats.items():
        if not key.startswith("miner_") or not isinstance(val, dict):
            continue
        if val.get("status") != "ok":
            continue
        for entry in val.get("algorithms", []) or []:
            name = (entry.get("algorithm") or "unknown").strip().lower()
            algo_totals[name] = algo_totals.get(name, 0.0) + algo_hashrate_for_mode(entry, mode)

    return total_watts, algo_totals


# ================================================================
# SYSTEMD HELPERS
# ================================================================
def service_is_active(service_name):
    try:
        result = subprocess.run(
            ["systemctl", "is-active", service_name],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() == "active"
    except Exception as e:
        log(f"[systemd] Error checking {service_name}: {e}")
        return False


def docker_status():
    """Returns one of "containers_running", "no_containers", or
    "unavailable".

    Mirrors docker_events_universal.sh's own is_docker_running() /
    any_container_running() checks:
      - "containers_running": a docker workload has taken over - it
        intentionally stops the local miner, and docker_events_{gpu,cpu}
        .service stays "active" the whole time (it's a Type=simple wrapper
        that never exits), so service_is_active alone can't detect this.
      - "unavailable": the docker CLI isn't installed, or the docker
        daemon isn't responding. Callers treat this the same as
        "no_containers" - a rig that simply doesn't use docker should
        still get normal hashrate/watts checks, not be permanently
        skipped.
      - "no_containers": docker is installed and reachable, and nothing
        is running under it - safe to run the normal hashrate/watts
        checks."""
    try:
        result = subprocess.run(
            ["docker", "ps", "-q"],
            capture_output=True, text=True, timeout=5
        )
    except FileNotFoundError:
        return "unavailable"
    except Exception as e:
        log(f"[docker] Error checking Docker: {e}")
        return "unavailable"

    if result.returncode != 0:
        return "unavailable"

    return "containers_running" if result.stdout.strip() else "no_containers"


def restart_service(service_name):
    log(f"[systemd] Restarting {service_name} ...")
    try:
        result = subprocess.run(
            ["systemctl", "restart", service_name],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            log(f"[systemd] {service_name} restarted successfully")
        else:
            log(f"[systemd] Restart of {service_name} exited {result.returncode}: {result.stderr.strip()}")
    except Exception as e:
        log(f"[systemd] Error restarting {service_name}: {e}")


# ================================================================
# MAIN LOOP
# ================================================================
def main():
    ap = argparse.ArgumentParser(description="RigCloud GPU/CPU watts+hashrate watchdog")
    ap.add_argument("--mode", choices=["gpu", "cpu"], required=True)
    ap.add_argument("--service", required=True, help="systemd unit to restart on failure, e.g. docker_events_gpu.service")
    ap.add_argument("--conf", default="/home/user/rigcloud-watchdog.conf")
    ap.add_argument("--interval", type=int, default=60, help="seconds between checks")
    args = ap.parse_args()

    log(f"Starting - mode={args.mode} service={args.service} conf={args.conf} interval={args.interval}s")

    consecutive_fails = 0
    last_restart_ts = 0.0

    while True:
        try:
            # "unavailable" (docker not installed/reachable) is treated the
            # same as "no_containers" - only an actual running container
            # should make the watchdog back off.
            if docker_status() == "containers_running":
                if consecutive_fails:
                    log("[skip] Docker container(s) running - docker workload has taken over, resetting fail counter")
                consecutive_fails = 0
                time.sleep(args.interval)
                continue

            if not service_is_active(args.service):
                if consecutive_fails:
                    log(f"[skip] {args.service} is not active, resetting fail counter")
                consecutive_fails = 0
                time.sleep(args.interval)
                continue

            conf = load_watchdog_conf(args.conf)
            total_watts, algo_totals = collect_snapshot(args.mode)

            if not algo_totals:
                # Service is active but nothing is reporting a hashrate at
                # all - treat as a DEFAULT-thresholds failure (miner isn't
                # really running, even though the wrapper service is "up").
                algo_totals = {"(none detected)": 0.0}

            failing_this_check = []
            for algo, hashrate in algo_totals.items():
                t = thresholds_for(conf, algo)
                reasons = []
                if t["min_hashrate_hs"] > 0 and hashrate < t["min_hashrate_hs"]:
                    reasons.append(f"hashrate {hashrate:.0f} H/s < min {t['min_hashrate_hs']:.0f} H/s")
                if args.mode == "gpu" and t["min_watts_total"] > 0 and total_watts < t["min_watts_total"]:
                    reasons.append(f"GPU watts {total_watts:.1f}W < min {t['min_watts_total']:.1f}W")
                if reasons:
                    failing_this_check.append((algo, t, reasons))

            if failing_this_check:
                consecutive_fails += 1
                # Use the tightest (smallest) grace/cooldown among the
                # currently-failing algos so a stricter algo's settings
                # aren't diluted by a looser one also being active.
                grace_checks = min(t["grace_checks"] for _, t, _ in failing_this_check)
                cooldown_seconds = min(t["cooldown_seconds"] for _, t, _ in failing_this_check)

                summary = "; ".join(f"{algo}: {', '.join(reasons)}" for algo, _, reasons in failing_this_check)
                log(f"[check] FAIL ({consecutive_fails}/{grace_checks}): {summary}")

                if consecutive_fails >= grace_checks:
                    since_last = time.time() - last_restart_ts
                    if since_last >= cooldown_seconds:
                        log(f"[ALERT] {args.service} unhealthy for {consecutive_fails} consecutive checks - {summary}")
                        restart_service(args.service)
                        last_restart_ts = time.time()
                        consecutive_fails = 0
                    else:
                        log(f"[check] Grace threshold hit but still in cooldown ({since_last:.0f}s / {cooldown_seconds}s) - not restarting again yet")
            else:
                if consecutive_fails:
                    log("[check] OK - healthy again, resetting fail counter")
                consecutive_fails = 0
                algo_summary = ", ".join(f"{a}: {h:.0f} H/s" for a, h in algo_totals.items())
                watts_summary = f", GPU watts: {total_watts:.1f}W" if args.mode == "gpu" else ""
                log(f"[check] OK - {algo_summary}{watts_summary}")

        except Exception as e:
            log(f"[error] Unexpected error during check: {e}")

        time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("Shutdown requested by user")
EOF

sudo chmod +x /usr/local/bin/rigcloud_watchdog.py

# -- write the algo-threshold conf, but only if it doesn't already exist,
#    so re-running this deploy script never clobbers your edits --
if [[ ! -f /home/user/rigcloud-watchdog.conf ]]; then
    sudo tee /home/user/rigcloud-watchdog.conf > /dev/null <<'EOF'
# ALGO,MIN_HASHRATE_HS,MIN_WATTS_TOTAL,GRACE_CHECKS,COOLDOWN_SECONDS
DEFAULT,1,20,3,600

# ---- example GPU algos - tune to your actual cards/pools ----
kheavyhash,50000000,120,3,600
keryxhash,1000000,60,3,600
verushash,3000,70,3,600
zhash,20,90,3,600

# keryxd is a node process, not a hasher - only checked for being
# "active" at all (both thresholds disabled)
keryxd-node,0,0,3,600
EOF
    echo "Wrote default /home/user/rigcloud-watchdog.conf - edit thresholds to match your rigs, then restart the watchdog services."
else
    echo "/home/user/rigcloud-watchdog.conf already exists - leaving it as-is."
fi

# -- write GPU watchdog service --
sudo tee /etc/systemd/system/rigcloud_watchdog_gpu.service > /dev/null <<'EOF'
[Unit]
Description=RigCloud GPU Watts/Hashrate Watchdog
After=docker_events_gpu.service
# Soft dependency only (no Requires=) - the watchdog should keep running
# and logging even if docker_events_gpu.service is briefly down, since
# that's exactly the condition it needs to detect.

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/rigcloud_watchdog.py \
    --mode gpu \
    --service docker_events_gpu.service \
    --conf /home/user/rigcloud-watchdog.conf \
    --interval 60
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# -- write CPU watchdog service --
sudo tee /etc/systemd/system/rigcloud_watchdog_cpu.service > /dev/null <<'EOF'
[Unit]
Description=RigCloud CPU Hashrate Watchdog
After=docker_events_cpu.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/rigcloud_watchdog.py \
    --mode cpu \
    --service docker_events_cpu.service \
    --conf /home/user/rigcloud-watchdog.conf \
    --interval 60
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl enable rigcloud_watchdog_gpu.service
sudo systemctl restart rigcloud_watchdog_gpu.service

sudo systemctl enable rigcloud_watchdog_cpu.service
sudo systemctl restart rigcloud_watchdog_cpu.service

# watch logs
sudo journalctl -u rigcloud_watchdog_gpu.service -f
sudo journalctl -u rigcloud_watchdog_cpu.service -f
