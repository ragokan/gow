#!/usr/bin/env python3
"""Render the raw bombardier + resource samples into a markdown report."""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "results", "raw")
APPS = [("go", "Go (chi+pgx+sqlc)"), ("dotnet", ".NET (Minimal API+Npgsql+Dapper)")]
SCENARIOS = [
    ("health", "GET /health (no DB)"),
    ("read_one", "GET /users/{id}"),
    ("list_20", "GET /users?limit=20"),
    ("list_100", "GET /users?limit=100"),
    ("update", "PUT /users/{id}"),
    ("create", "POST /users"),
    ("delete", "DELETE /users/{id}"),
]


def load_bombardier(app, name):
    path = os.path.join(RAW, app, f"{name}.bombardier.json")
    with open(path) as f:
        s = f.read()
    return json.loads(s[s.index("{"):])["result"]


def load_res(app, name):
    with open(os.path.join(RAW, app, f"{name}.resources.json")) as f:
        return json.load(f)


def fmt(n, d=1):
    return f"{n:,.{d}f}"


def errors(r):
    return (r.get("req4xx", 0) or 0) + (r.get("req5xx", 0) or 0) + (r.get("others", 0) or 0)


def main():
    out = []
    out.append("## Benchmark Results\n")

    # Idle resources
    out.append("### Idle resource usage (server running, zero traffic)\n")
    out.append("| App | CPU % (avg / max) | RSS MiB (avg / max) |")
    out.append("|---|---|---|")
    for app, label in APPS:
        r = load_res(app, "idle")
        out.append(f"| {label} | {r['cpu_pct_avg']} / {r['cpu_pct_max']} | "
                   f"{r['rss_mib_avg']} / {r['rss_mib_max']} |")
    out.append("")

    # Throughput table
    out.append("### Throughput (requests/sec, higher is better)\n")
    out.append("| Scenario | Go RPS | .NET RPS | Winner | Δ |")
    out.append("|---|---:|---:|---|---:|")
    for name, label in SCENARIOS:
        g = load_bombardier("go", name)["rps"]["mean"]
        n = load_bombardier("dotnet", name)["rps"]["mean"]
        win = "Go" if g > n else ".NET"
        ratio = (max(g, n) / min(g, n)) if min(g, n) > 0 else float("inf")
        out.append(f"| {label} | {fmt(g)} | {fmt(n)} | **{win}** | {ratio:.2f}x |")
    out.append("")

    # Latency table
    out.append("### Latency (ms, lower is better)\n")
    out.append("| Scenario | Go avg | Go p99 | .NET avg | .NET p99 |")
    out.append("|---|---:|---:|---:|---:|")
    for name, label in SCENARIOS:
        gr = load_bombardier("go", name)
        nr = load_bombardier("dotnet", name)
        gp = gr["latency"].get("percentiles", {}).get("99", 0) / 1000
        npc = nr["latency"].get("percentiles", {}).get("99", 0) / 1000
        out.append(f"| {label} | {gr['latency']['mean']/1000:.3f} | {gp:.3f} | "
                   f"{nr['latency']['mean']/1000:.3f} | {npc:.3f} |")
    out.append("")

    # Resource-under-load table
    out.append("### Resource usage under load (per scenario)\n")
    out.append("| Scenario | Go CPU% avg/max | Go RSS MiB avg/max | .NET CPU% avg/max | .NET RSS MiB avg/max |")
    out.append("|---|---|---|---|---|")
    for name, label in SCENARIOS:
        g = load_res("go", name)
        n = load_res("dotnet", name)
        out.append(f"| {label} | {g['cpu_pct_avg']}/{g['cpu_pct_max']} | "
                   f"{g['rss_mib_avg']}/{g['rss_mib_max']} | "
                   f"{n['cpu_pct_avg']}/{n['cpu_pct_max']} | "
                   f"{n['rss_mib_avg']}/{n['rss_mib_max']} |")
    out.append("")

    # Error check
    out.append("### Error counts (non-2xx responses)\n")
    out.append("| Scenario | Go errors | .NET errors |")
    out.append("|---|---:|---:|")
    for name, label in SCENARIOS:
        out.append(f"| {label} | {errors(load_bombardier('go', name))} | "
                   f"{errors(load_bombardier('dotnet', name))} |")
    out.append("")

    report = "\n".join(out)
    dest = os.path.join(ROOT, "results", "RESULTS.md")
    with open(dest, "w") as f:
        f.write(report)
    print(report)
    print(f"\nWrote {dest}")


if __name__ == "__main__":
    sys.exit(main())
