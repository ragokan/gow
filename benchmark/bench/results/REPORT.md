# Go vs .NET — CRUD Benchmark Results

_Generated: 2026-06-13 15:22:16 UTC_

**Run configuration**

- duration: `120s`
- connections: `256`
- timeout: `10s`
- seed_rows: `1000`
- sample_interval_s: `0.5`
- app_cpus: `1.5`
- app_mem: `1g`
- db_cpus: `1.5`
- db_mem: `1g`
- host_cpus: `4`
- dotnet_mode: `Native AOT + raw Npgsql`
- go_mode: `compiled + sqlc/pgx`

## Idle resource usage (container at rest)

| App | CPU % (avg) | Memory MiB (avg) | Memory MiB (max) |
|-----|------------:|-----------------:|-----------------:|
| Go (chi + sqlc + pgx) | 0.19 | 4.0 | 6.8 |
| .NET 10 AOT (Minimal API + Npgsql) | 0.17 | 13.1 | 15.0 |

## Throughput & latency (per scenario)

Higher RPS is better; lower latency is better.

### GET /health (no DB)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi + sqlc + pgx) | 35,750 | 7.16 | 20.51 | 59.06 | 4,288,481 | 0 |
| .NET 10 AOT (Minimal API + Npgsql) | 38,046 | 6.72 | 15.62 | 47.57 | 4,565,971 | 0 |

> **.NET** is faster by **1.06x** (35,750 vs 38,046 req/s).

### GET /users/{id} (read one)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi + sqlc + pgx) | 8,605 | 29.76 | 44.43 | 91.71 | 1,032,096 | 0 |
| .NET 10 AOT (Minimal API + Npgsql) | 6,948 | 36.99 | 54.16 | 167.44 | 830,431 | 0 |

> **Go** is faster by **1.24x** (8,605 vs 6,948 req/s).

### GET /users?limit=20 (list)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi + sqlc + pgx) | 5,635 | 45.49 | 63.26 | 99.98 | 675,178 | 0 |
| .NET 10 AOT (Minimal API + Npgsql) | 5,710 | 44.88 | 61.93 | 186.41 | 684,447 | 0 |

> **.NET** is faster by **1.01x** (5,635 vs 5,710 req/s).

### PUT /users/{id} (update)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi + sqlc + pgx) | 856 | 298.93 | 446.33 | 771.02 | 102,881 | 0 |
| .NET 10 AOT (Minimal API + Npgsql) | 900 | 284.09 | 421.86 | 714.41 | 108,266 | 0 |

> **.NET** is faster by **1.05x** (856 vs 900 req/s).

### POST /users (create)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi + sqlc + pgx) | 5,555 | 46.09 | 77.30 | 751.81 | 666,517 | 0 |
| .NET 10 AOT (Minimal API + Npgsql) | 5,130 | 49.91 | 81.38 | 314.38 | 615,464 | 0 |

> **Go** is faster by **1.08x** (5,555 vs 5,130 req/s).

## Resource usage under load (per scenario)

Continuous samples (every sample interval) over the full run. CPU % is Docker's metric (100% = 1 vCPU; cap = configured limit). `db` rows show the shared Postgres container during that app's run.

### GET /health (no DB)

| Container | CPU % avg | CPU % p95 | CPU % max | Mem MiB avg | Mem MiB max |
|-----------|----------:|----------:|----------:|------------:|------------:|
| Go (chi + sqlc + pgx) | 133.1 | 139.1 | 139.9 | 15.1 | 23.7 |
| Postgres (during go) | 2.1 | 2.3 | 14.7 | 114.0 | 147.2 |
| .NET 10 AOT (Minimal API + Npgsql) | 122.4 | 126.5 | 127.1 | 25.2 | 38.2 |
| Postgres (during dotnet) | 2.2 | 2.3 | 12.6 | 211.8 | 259.2 |

### GET /users/{id} (read one)

| Container | CPU % avg | CPU % p95 | CPU % max | Mem MiB avg | Mem MiB max |
|-----------|----------:|----------:|----------:|------------:|------------:|
| Go (chi + sqlc + pgx) | 101.3 | 109.3 | 116.4 | 23.9 | 24.2 |
| Postgres (during go) | 90.7 | 95.6 | 97.1 | 147.6 | 150.3 |
| .NET 10 AOT (Minimal API + Npgsql) | 114.9 | 119.6 | 120.9 | 48.8 | 66.1 |
| Postgres (during dotnet) | 128.1 | 134.3 | 136.2 | 259.8 | 261.1 |

### GET /users?limit=20 (list)

| Container | CPU % avg | CPU % p95 | CPU % max | Mem MiB avg | Mem MiB max |
|-----------|----------:|----------:|----------:|------------:|------------:|
| Go (chi + sqlc + pgx) | 113.9 | 118.8 | 119.7 | 26.8 | 27.5 |
| Postgres (during go) | 96.9 | 101.9 | 103.7 | 150.1 | 152.4 |
| .NET 10 AOT (Minimal API + Npgsql) | 120.8 | 124.5 | 125.7 | 54.1 | 64.6 |
| Postgres (during dotnet) | 135.8 | 140.5 | 142.0 | 262.5 | 264.6 |

### PUT /users/{id} (update)

| Container | CPU % avg | CPU % p95 | CPU % max | Mem MiB avg | Mem MiB max |
|-----------|----------:|----------:|----------:|------------:|------------:|
| Go (chi + sqlc + pgx) | 39.0 | 42.7 | 44.1 | 25.9 | 25.9 |
| Postgres (during go) | 144.5 | 154.1 | 158.4 | 153.8 | 155.1 |
| .NET 10 AOT (Minimal API + Npgsql) | 55.9 | 59.2 | 60.0 | 68.6 | 75.7 |
| Postgres (during dotnet) | 146.5 | 156.5 | 157.8 | 265.5 | 266.9 |

### POST /users (create)

| Container | CPU % avg | CPU % p95 | CPU % max | Mem MiB avg | Mem MiB max |
|-----------|----------:|----------:|----------:|------------:|------------:|
| Go (chi + sqlc + pgx) | 98.1 | 104.1 | 105.9 | 26.5 | 26.8 |
| Postgres (during go) | 108.4 | 114.8 | 121.6 | 173.7 | 212.0 |
| .NET 10 AOT (Minimal API + Npgsql) | 100.4 | 106.5 | 107.2 | 59.2 | 71.5 |
| Postgres (during dotnet) | 140.5 | 144.9 | 147.3 | 298.7 | 310.4 |

## Memory footprint summary

| App | Idle (MiB) | Peak under load (MiB) |
|-----|-----------:|----------------------:|
| Go (chi + sqlc + pgx) | 4.0 | 27.5 |
| .NET 10 AOT (Minimal API + Npgsql) | 13.1 | 75.7 |

## Summary — Req/s by scenario

| Scenario | Go req/s | .NET req/s | Winner | Factor |
|----------|---------:|-----------:|--------|-------:|
| GET /health (no DB) | 35,750 | 38,046 | .NET | 1.06x |
| GET /users/{id} (read one) | 8,605 | 6,948 | Go | 1.24x |
| GET /users?limit=20 (list) | 5,635 | 5,710 | .NET | 1.01x |
| PUT /users/{id} (update) | 856 | 900 | .NET | 1.05x |
| POST /users (create) | 5,555 | 5,130 | Go | 1.08x |

## Interpretation

Both apps now use a **raw, typed-SQL** data layer (Go: `sqlc`+`pgx`; .NET: hand-written `Npgsql` commands), and the .NET app is compiled with **Native AOT** (`PublishAot`, source-generated JSON, slim host, server GC, `NpgsqlDataSource` with auto-prepare). This is a much closer apples-to-apples comparison than ORM-vs-sqlc.

- **`GET /health` (no DB):** pure HTTP throughput; closest to a raw framework comparison.
- **Reads/inserts:** dominated by the driver + serialization path.
- **`PUT` (update):** every request updates the *same* row, so PostgreSQL row-level lock contention dominates and both apps become database-bound — this measures the DB under hot-row contention, not the framework (note the apps' CPU sits well below cap while Postgres CPU climbs).
- **Memory:** Native AOT removes the JIT and trims the runtime, so the .NET footprint is far smaller than a JIT build — compare the idle/peak numbers. Go is still the leaner of the two.

> Absolute throughput is bounded by the 4-core host shared between the app (1.5 vCPU), Postgres (1.5 vCPU), the load generator and the samplers — so read the **relative** factors, which both apps face under identical conditions, rather than the raw req/s ceiling.

