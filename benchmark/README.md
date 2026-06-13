# Go vs .NET CRUD Benchmark

A like-for-like HTTP CRUD benchmark comparing a **Go** stack and a **.NET**
stack against the **same PostgreSQL database**, under **equal CPU/memory
budgets**, driven by [`bombardier`](https://github.com/codesenberg/bombardier).
Both services expose an identical `users` CRUD API and run the same SQL.

> Results live in [`results/RESULTS.md`](results/RESULTS.md) and the raw
> per-scenario JSON is under [`results/raw/`](results/raw/).

## The two services

| | Go service (`go-api/`) | .NET service (`dotnet-api/`) |
|---|---|---|
| Language / runtime | Go 1.25 (native binary) | .NET 10.0.301 (**Native AOT** binary) |
| HTTP framework | [chi](https://github.com/go-chi/chi) v5.3.0 | ASP.NET Core Minimal APIs (`CreateSlimBuilder`) |
| DB driver | [pgx](https://github.com/jackc/pgx) v5.10.0 (pgxpool) | [Npgsql](https://www.npgsql.org/) 9.0.3 |
| Query layer | [sqlc](https://sqlc.dev) v1.31.1 (generated, type-safe raw SQL) | raw Npgsql, hand-mapped readers |
| Prepared statements | yes (pgx statement cache) | yes (`Max Auto Prepare`) |
| JSON | `encoding/json` | `System.Text.Json` (source-generated) |
| GC / memory | Go GC | Server GC (concurrent) |
| Migrations | [goose](https://github.com/pressly/goose) v3.27.1 | (shares the goose-migrated schema) |
| Database | PostgreSQL 16.13 | PostgreSQL 16.13 |

**Optimizations applied (both sides are natively compiled, prepared, pooled):**

* .NET is published as a **Native AOT** binary (no JIT warmup), with **Server
  GC**, **auto-prepared statements**, source-generated JSON, and `TypedResults`.
* **Why raw Npgsql instead of Dapper or EF Core?** Dapper's runtime IL-emit
  mapping is not AOT/trim-safe, and EF Core adds change-tracking + LINQ
  translation that sqlc simply doesn't do. Hand-mapped Npgsql readers are the
  fastest, fully AOT-safe path and are the closest analogue to sqlc's generated
  raw SQL — keeping the comparison about runtime + driver + framework, not ORM
  overhead.
* Go's pgx already caches prepared statements, so both sides use prepared
  statements over a 10–50 connection pool — apples-to-apples.

## API (identical on both)

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Liveness, no DB access |
| `POST` | `/users` | Create a user |
| `GET` | `/users/{id}` | Fetch one user |
| `GET` | `/users?limit=&offset=` | List users |
| `PUT` | `/users/{id}` | Update a user |
| `DELETE` | `/users/{id}` | Delete a user |

Schema: `users(id, name, email, age, created_at, updated_at)`. The `email`
column is indexed but **intentionally not unique** so the `POST` benchmark
(which replays a single request body) can insert without conflicts.

## How "equal resources" is enforced

* **CPU pinning** — both apps are pinned to the *same* cores via
  `taskset -c 0,1` (2 cores). The Go app additionally runs with `GOMAXPROCS=2`;
  .NET sees 2 logical CPUs through the affinity mask. The load generator,
  `bombardier`, is pinned to the *other* cores (`-c 2,3`) so it never steals CPU
  from the service under test.
* **Same connection pool** — both use a 10–50 connection pool.
* **Sequential runs** — the two services are never benchmarked at the same
  time, so neither competes with the other for Postgres or memory.
* **Identical data** — the `users` table is reset and re-seeded with the same
  10,000 rows before each service's run.
* **Production-like config** — the .NET app's per-request Information logging is
  disabled (set to `Warning`) so we measure the server, not the console logger;
  the Go app does no per-request logging.

## What is measured

A **single continuous sampler** (`scripts/sample_continuous.sh`, reads
`/proc/<pid>` + `/proc/stat`) records **once per second for the entire lifetime
of each server** — idle, warmup, every scenario, and the gaps between them:

* **app CPU%** — relative to a single core (100% = one fully-busy core; max
  200% with the 2-core pin).
* **app RSS** (MiB) — resident memory of the service.
* **system CPU%** — whole-machine busy across all 4 cores (app + Postgres +
  bombardier), for context.

The full time-series lands in `results/raw/<app>/resources.csv` (with a `phase`
column), and `results/raw/<app>/phases.csv` records each scenario's start/end
timestamps so per-scenario stats are sliced exactly. bombardier provides
**throughput** (req/s), **latency** (avg + percentiles), and **error counts**.

Each scenario runs for **120 seconds** at **256 concurrent connections**; the
idle window is 20s.

### Note on the `PUT`/`UPDATE` scenario

bombardier replays one fixed request, so the update scenario hammers a single
row (`/users/1`). Concurrent updates to one row serialize on a Postgres row
lock, so that scenario is dominated by **DB lock contention** (identically for
both apps) rather than framework speed. The `health`, `read`, `list`, and
`create` scenarios are the cleaner framework/runtime comparisons.

## Running it yourself

Prereqs: PostgreSQL running locally with a `bench`/`benchpass` role owning a
`benchdb` database, plus Go, the .NET 10 SDK, `bombardier`, `sqlc`, `goose`, and
the Native AOT toolchain (`clang`, `zlib1g-dev`).

```sh
# 1. migrate + generate
goose -dir migrations postgres "$DSN" up
cd go-api && sqlc generate && cd ..

# 2. build both (the .NET build is a Native AOT publish)
(cd go-api && go build -o ../bin/go-api .)
(cd dotnet-api && dotnet publish -c Release -r linux-x64 -o ../bin/dotnet-api)

# 3. run the full benchmark (writes results/raw/**)
DURATION=120 CONNS=256 SEED_ROWS=10000 bash scripts/run_benchmark.sh

# 4. render the markdown report
python3 scripts/summarize.py
```

Tunables (env vars): `DURATION`, `CONNS`, `SEED_ROWS`, `APP_CORES`,
`LOAD_CORES`, `IDLE_SECS`, `WARMUP_SECS`.

## Layout

```
benchmark/
├── migrations/            # goose migration (single source of truth for schema)
├── go-api/                # Go service (chi + pgx + sqlc)
│   ├── db/query.sql       # sqlc queries
│   └── internal/sqlcdb/   # sqlc-generated code
├── dotnet-api/            # .NET service (Minimal API + Npgsql, Native AOT)
├── scripts/
│   ├── seed.sh             # reset + seed the users table
│   ├── sample_continuous.sh# whole-run 1s CPU/RSS recorder (app + system)
│   ├── run_benchmark.sh    # orchestrator
│   └── summarize.py        # raw results -> results/RESULTS.md
└── results/                # RESULTS.md, run.log, and raw/<app>/{*.bombardier.json,
                            #   resources.csv, phases.csv}
```
