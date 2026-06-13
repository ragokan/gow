# Go vs .NET — CRUD Benchmark Results

_Generated: 2026-06-13 13:46:52 UTC_

**Run configuration**

- duration: `60s`
- connections: `256`
- timeout: `10s`
- seed_rows: `1000`
- app_cpus: `1.5`
- app_mem: `1g`
- db_cpus: `1.5`
- db_mem: `1g`
- host_cpus: `4`

## Idle resource usage (container at rest)

| App | CPU % (avg) | Memory MiB (avg) |
|-----|------------:|-----------------:|
| Go (chi+sqlc+pgx) | 0.02 | 3.7 |
| .NET (Minimal API+EF Core) | 0.01 | 40.6 |

## Throughput & latency (per scenario)

Higher RPS is better; lower latency is better. Each scenario ran for the configured duration at the configured concurrency.

### GET /health (no DB)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi+sqlc+pgx) | 58,616 | 4.36 | 12.36 | 39.52 | 3,517,214 | 0 |
| .NET (Minimal API+EF Core) | 61,713 | 4.15 | 9.96 | 44.09 | 3,701,830 | 0 |

> **.NET** is faster by **1.05x** (58,616 vs 61,713 req/s).

### GET /users/{id} (read one)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi+sqlc+pgx) | 14,551 | 17.60 | 27.25 | 68.04 | 872,545 | 0 |
| .NET (Minimal API+EF Core) | 8,802 | 29.13 | 47.04 | 156.21 | 527,229 | 0 |

> **Go** is faster by **1.65x** (14,551 vs 8,802 req/s).

### GET /users?limit=20 (list)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi+sqlc+pgx) | 8,631 | 29.66 | 42.92 | 75.32 | 517,879 | 0 |
| .NET (Minimal API+EF Core) | 7,876 | 32.55 | 48.71 | 118.79 | 471,983 | 0 |

> **Go** is faster by **1.10x** (8,631 vs 7,876 req/s).

### PUT /users/{id} (update)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi+sqlc+pgx) | 802 | 318.24 | 445.63 | 691.21 | 48,390 | 0 |
| .NET (Minimal API+EF Core) | 844 | 302.75 | 457.10 | 747.72 | 50,867 | 0 |

> **.NET** is faster by **1.05x** (802 vs 844 req/s).

### POST /users (create)

| App | Req/s | Latency mean (ms) | Latency p99 (ms) | Latency max (ms) | 2xx | errors |
|-----|------:|------------------:|-----------------:|-----------------:|----:|-------:|
| Go (chi+sqlc+pgx) | 8,159 | 31.37 | 59.52 | 144.15 | 489,608 | 0 |
| .NET (Minimal API+EF Core) | 5,682 | 45.06 | 67.41 | 179.02 | 340,967 | 0 |

> **Go** is faster by **1.44x** (8,159 vs 5,682 req/s).

## Resource usage under load (per scenario)

CPU % is Docker's metric (100% = 1 vCPU; cap is the configured limit). Memory is container RSS.

### GET /health (no DB)

| App | CPU % avg | CPU % max | Mem MiB avg | Mem MiB max |
|-----|----------:|----------:|------------:|------------:|
| Go (chi+sqlc+pgx) | 124.7 | 136.1 | 14.9 | 15.5 |
| .NET (Minimal API+EF Core) | 117.3 | 131.7 | 68.3 | 84.0 |

### GET /users/{id} (read one)

| App | CPU % avg | CPU % max | Mem MiB avg | Mem MiB max |
|-----|----------:|----------:|------------:|------------:|
| Go (chi+sqlc+pgx) | 95.5 | 105.5 | 24.1 | 24.5 |
| .NET (Minimal API+EF Core) | 130.8 | 149.3 | 144.5 | 192.4 |

### GET /users?limit=20 (list)

| App | CPU % avg | CPU % max | Mem MiB avg | Mem MiB max |
|-----|----------:|----------:|------------:|------------:|
| Go (chi+sqlc+pgx) | 111.2 | 119.9 | 27.2 | 27.6 |
| .NET (Minimal API+EF Core) | 132.0 | 143.6 | 142.5 | 159.4 |

### PUT /users/{id} (update)

| App | CPU % avg | CPU % max | Mem MiB avg | Mem MiB max |
|-----|----------:|----------:|------------:|------------:|
| Go (chi+sqlc+pgx) | 29.5 | 32.8 | 25.4 | 25.5 |
| .NET (Minimal API+EF Core) | 84.0 | 92.9 | 166.5 | 174.4 |

### POST /users (create)

| App | CPU % avg | CPU % max | Mem MiB avg | Mem MiB max |
|-----|----------:|----------:|------------:|------------:|
| Go (chi+sqlc+pgx) | 87.5 | 95.5 | 25.9 | 26.2 |
| .NET (Minimal API+EF Core) | 111.7 | 124.4 | 167.8 | 169.6 |

## Memory footprint summary

| App | Idle (MiB) | Peak under load (MiB) |
|-----|-----------:|----------------------:|
| Go (chi+sqlc+pgx) | 3.7 | 27.6 |
| .NET (Minimal API+EF Core) | 40.6 | 192.4 |

## Summary — Req/s by scenario

| Scenario | Go req/s | .NET req/s | Winner | Factor |
|----------|---------:|-----------:|--------|-------:|
| GET /health (no DB) | 58,616 | 61,713 | .NET | 1.05x |
| GET /users/{id} (read one) | 14,551 | 8,802 | Go | 1.65x |
| GET /users?limit=20 (list) | 8,631 | 7,876 | Go | 1.10x |
| PUT /users/{id} (update) | 802 | 844 | .NET | 1.05x |
| POST /users (create) | 8,159 | 5,682 | Go | 1.44x |

## Interpretation

- **`GET /health` (no DB):** roughly a tie (~60k req/s). Both stacks have extremely fast HTTP pipelines; .NET's Kestrel + Minimal API edges it out slightly on pure request handling.
- **Reads (`read_one`, `list`):** Go leads, most clearly on the point read (~1.6x). `sqlc`+`pgx` map rows directly into structs, while EF Core adds LINQ translation and a materialization pipeline (even with `AsNoTracking`).
- **`POST` (create):** Go leads (~1.4x) — leaner insert + serialization path.
- **`PUT` (update):** essentially a tie at low throughput. Every request updates the *same* row, so PostgreSQL row-level lock contention dominates and both apps become database-bound — this measures the DB under hot-row contention, not the framework. Note the apps' CPU stays well below cap here.
- **Memory:** Go is dramatically leaner — single-digit/tens of MiB vs the .NET runtime's tens-to-hundreds of MiB (idle and under load).
- **CPU:** for DB-backed work .NET generally consumes more CPU per request; where an app sits below its 1.5 vCPU cap it was waiting on Postgres, not compute.

> Caveat: this compares each ecosystem's *idiomatic* stack — raw typed SQL (`sqlc`) vs a full ORM (EF Core). A Dapper-based .NET app would narrow the read/insert gaps considerably.

