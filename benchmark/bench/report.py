#!/usr/bin/env python3
"""Aggregate bombardier JSON + continuous resource CSVs into a Markdown report."""
import csv
import json
import os
import sys
from datetime import datetime, timezone

APPS = ["go", "dotnet"]
APP_LABEL = {
    "go": "Go (chi + sqlc + pgx)",
    "dotnet": ".NET 10 AOT (Minimal API + Npgsql)",
}
SCENARIOS = [
    ("health", "GET /health (no DB)"),
    ("read_one", "GET /users/{id} (read one)"),
    ("list", "GET /users?limit=20 (list)"),
    ("update", "PUT /users/{id} (update)"),
    ("create", "POST /users (create)"),
]


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def pct(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    k = (len(sorted_vals) - 1) * (p / 100.0)
    lo, hi = int(k), min(int(k) + 1, len(sorted_vals) - 1)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (k - lo)


def stats_summary(path):
    if not os.path.exists(path):
        return None
    cpus, mems = [], []
    with open(path) as f:
        rows = list(csv.DictReader(f))
    # drop the first sample (CPU differencer has no baseline yet)
    for row in rows[1:]:
        try:
            cpus.append(float(row["cpu_perc"]))
            mems.append(float(row.get("mem_mib") or row.get("mem_used_mib")))
        except (ValueError, KeyError, TypeError):
            pass
    if not cpus:
        return None
    cs = sorted(cpus)
    return {
        "cpu_avg": sum(cpus) / len(cpus),
        "cpu_p95": pct(cs, 95),
        "cpu_max": max(cpus),
        "mem_avg": sum(mems) / len(mems),
        "mem_max": max(mems),
        "n": len(cpus),
    }


def metrics(res_dir, app, skey):
    data = load_json(os.path.join(res_dir, f"{app}_{skey}.json"))
    if not data:
        return None
    r = data["result"]
    lat = r.get("latency", {})
    rps = r.get("rps", {})
    p = lat.get("percentiles", {}) or {}
    total = r["req1xx"] + r["req2xx"] + r["req3xx"] + r["req4xx"] + r["req5xx"] + r["others"]
    return {
        "rps": rps.get("mean", 0),
        "lat_mean_ms": lat.get("mean", 0) / 1000.0,
        "lat_p99_ms": (p.get("99") or 0) / 1000.0,
        "lat_max_ms": lat.get("max", 0) / 1000.0,
        "ok": r["req2xx"],
        "err": r["req4xx"] + r["req5xx"] + r["others"],
        "total": total,
        "stats": stats_summary(os.path.join(res_dir, f"{app}_{skey}_stats.csv")),
        "db_stats": stats_summary(os.path.join(res_dir, f"{app}_{skey}_db_stats.csv")),
    }


def fmt(x, d=0):
    return f"{x:,.{d}f}"


def main():
    res_dir = sys.argv[1] if len(sys.argv) > 1 else "results"
    out = []
    w = out.append

    w("# Go vs .NET — CRUD Benchmark Results")
    w("")
    w(f"_Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}_")
    w("")
    env = load_json(os.path.join(res_dir, "_meta.json")) or {}
    if env:
        w("**Run configuration**")
        w("")
        for k, v in env.items():
            w(f"- {k}: `{v}`")
        w("")

    # Idle usage
    w("## Idle resource usage (container at rest)")
    w("")
    w("| App | CPU % (avg) | Memory MiB (avg) | Memory MiB (max) |")
    w("|-----|------------:|-----------------:|-----------------:|")
    for app in APPS:
        s = stats_summary(os.path.join(res_dir, f"{app}_idle_stats.csv"))
        if s:
            w(f"| {APP_LABEL[app]} | {fmt(s['cpu_avg'],2)} | {fmt(s['mem_avg'],1)} | {fmt(s['mem_max'],1)} |")
    w("")

    # Per-scenario throughput / latency
    w("## Throughput & latency (per scenario)")
    w("")
    w("Higher RPS is better; lower latency is better.")
    w("")
    for skey, label in SCENARIOS:
        w(f"### {label}")
        w("")
        w("| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |")
        w("|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|")
        m = {}
        for app in APPS:
            mm = metrics(res_dir, app, skey)
            m[app] = mm
            if mm:
                w(f"| {APP_LABEL[app]} | {fmt(mm['rps'])} | {fmt(mm['lat_mean_ms'],2)} | "
                  f"{fmt(mm['lat_p99_ms'],2)} | {fmt(mm['lat_max_ms'],2)} | {fmt(mm['ok'])} | {fmt(mm['err'])} |")
        w("")
        if m.get("go") and m.get("dotnet") and m["dotnet"]["rps"] > 0:
            ratio = m["go"]["rps"] / m["dotnet"]["rps"]
            winner = "Go" if ratio >= 1 else ".NET"
            factor = ratio if ratio >= 1 else 1 / ratio
            w(f"> **{winner}** is faster by **{factor:.2f}x** "
              f"({fmt(m['go']['rps'])} vs {fmt(m['dotnet']['rps'])} req/s).")
            w("")

    # Resource usage under load
    w("## Resource usage under load (per scenario)")
    w("")
    w("Continuous samples (every sample interval) over the full run. CPU % is "
      "Docker's metric (100% = 1 vCPU; cap = configured limit). `db` rows show "
      "the shared Postgres container during that app's run.")
    w("")
    for skey, label in SCENARIOS:
        w(f"### {label}")
        w("")
        w("| Container | CPU % avg | CPU % p95 | CPU % max | Mem MiB avg | Mem MiB max |")
        w("|-----------|----------:|----------:|----------:|------------:|------------:|")
        for app in APPS:
            mm = metrics(res_dir, app, skey)
            if not mm:
                continue
            s = mm["stats"]
            if s:
                w(f"| {APP_LABEL[app]} | {fmt(s['cpu_avg'],1)} | {fmt(s['cpu_p95'],1)} | "
                  f"{fmt(s['cpu_max'],1)} | {fmt(s['mem_avg'],1)} | {fmt(s['mem_max'],1)} |")
            d = mm["db_stats"]
            if d:
                w(f"| Postgres (during {app}) | {fmt(d['cpu_avg'],1)} | {fmt(d['cpu_p95'],1)} | "
                  f"{fmt(d['cpu_max'],1)} | {fmt(d['mem_avg'],1)} | {fmt(d['mem_max'],1)} |")
        w("")

    # Memory footprint summary
    w("## Memory footprint summary")
    w("")
    w("| App | Idle (MiB) | Peak under load (MiB) |")
    w("|-----|-----------:|----------------------:|")
    for app in APPS:
        idle = stats_summary(os.path.join(res_dir, f"{app}_idle_stats.csv"))
        peak = 0.0
        for skey, _ in SCENARIOS:
            mm = metrics(res_dir, app, skey)
            if mm and mm["stats"]:
                peak = max(peak, mm["stats"]["mem_max"])
        idle_v = fmt(idle["mem_avg"], 1) if idle else "n/a"
        w(f"| {APP_LABEL[app]} | {idle_v} | {fmt(peak,1)} |")
    w("")

    # Summary table
    w("## Summary — Req/s by scenario")
    w("")
    w("| Scenario | Go req/s | .NET req/s | Winner | Factor |")
    w("|----------|---------:|-----------:|--------|-------:|")
    for skey, label in SCENARIOS:
        g = metrics(res_dir, "go", skey)
        d = metrics(res_dir, "dotnet", skey)
        if not g or not d or d["rps"] <= 0:
            continue
        ratio = g["rps"] / d["rps"]
        winner = "Go" if ratio >= 1 else ".NET"
        factor = ratio if ratio >= 1 else 1 / ratio
        w(f"| {label} | {fmt(g['rps'])} | {fmt(d['rps'])} | {winner} | {factor:.2f}x |")
    w("")

    w("## Interpretation")
    w("")
    w("Both apps now use a **raw, typed-SQL** data layer (Go: `sqlc`+`pgx`; "
      ".NET: hand-written `Npgsql` commands), and the .NET app is compiled with "
      "**Native AOT** (`PublishAot`, source-generated JSON, slim host, server GC, "
      "`NpgsqlDataSource` with auto-prepare). This is a much closer apples-to-apples "
      "comparison than ORM-vs-sqlc.")
    w("")
    w("- **`GET /health` (no DB):** pure HTTP throughput; closest to a raw "
      "framework comparison.")
    w("- **Reads/inserts:** dominated by the driver + serialization path.")
    w("- **`PUT` (update):** every request updates the *same* row, so PostgreSQL "
      "row-level lock contention dominates and both apps become database-bound — "
      "this measures the DB under hot-row contention, not the framework (note the "
      "apps' CPU sits well below cap while Postgres CPU climbs).")
    w("- **Memory:** Native AOT removes the JIT and trims the runtime, so the .NET "
      "footprint is far smaller than a JIT build — compare the idle/peak numbers. "
      "Go is still the leaner of the two.")
    w("")
    w("> Absolute throughput is bounded by the 4-core host shared between the app "
      "(1.5 vCPU), Postgres (1.5 vCPU), the load generator and the samplers — so "
      "read the **relative** factors, which both apps face under identical "
      "conditions, rather than the raw req/s ceiling.")
    w("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
