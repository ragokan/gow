#!/usr/bin/env python3
"""Continuously record a container's CPU% and memory via the Docker Engine API.

Usage: sampler.py <container_id> <out_csv> <interval_seconds>

Writes one row per sample: elapsed_s,cpu_perc,mem_mib  (100% CPU == 1 vCPU).
CPU% is computed from the delta between our own consecutive samples, so it does
not depend on the API's precpu snapshot. Stops cleanly on SIGTERM/SIGINT.
"""
import json
import signal
import subprocess
import sys
import time

cid, out, interval = sys.argv[1], sys.argv[2], float(sys.argv[3])
_run = {"go": True}


def _stop(*_):
    _run["go"] = False


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)


def sample():
    p = subprocess.run(
        ["curl", "-s", "--unix-socket", "/var/run/docker.sock",
         f"http://localhost/containers/{cid}/stats?stream=false"],
        capture_output=True, text=True,
    )
    return json.loads(p.stdout)


def mem_mib(s):
    m = s["memory_stats"]
    stats = m.get("stats", {})
    cache = stats.get("total_inactive_file", stats.get("inactive_file", 0))
    return max(0.0, (m.get("usage", 0) - cache)) / (1024 * 1024)


prev_total = prev_system = None
with open(out, "w") as f:
    f.write("elapsed_s,cpu_perc,mem_mib\n")
    start = time.time()
    while _run["go"]:
        try:
            s = sample()
            cpu_stats = s["cpu_stats"]
            total = cpu_stats["cpu_usage"]["total_usage"]
            system = cpu_stats.get("system_cpu_usage", 0)
            ncpu = cpu_stats.get("online_cpus") or 1
            if prev_total is not None and system > prev_system:
                cpu = (total - prev_total) / (system - prev_system) * ncpu * 100.0
            else:
                cpu = 0.0
            prev_total, prev_system = total, system
            f.write(f"{time.time() - start:.2f},{cpu:.1f},{mem_mib(s):.1f}\n")
            f.flush()
        except Exception:
            pass
        time.sleep(interval)
