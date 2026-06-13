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
| Language / runtime | Go 1.25 | .NET 10.0.301 |
| HTTP framework | [chi](https://github.com/go-chi/chi) v5.3.0 | ASP.NET Core Minimal APIs |
| DB driver | [pgx](https://github.com/jackc/pgx) v5.10.0 (pgxpool) | [Npgsql](https://www.npgsql.org/) 9.0.3 |
| Query layer | [sqlc](https://sqlc.dev) v1.31.1 (generated, type-safe raw SQL) | [Dapper](https://github.com/DapperLib/Dapper) 2.1.66 (raw SQL) |
| JSON | `encoding/json` | `System.Text.Json` (source-generated) |
| Migrations | [goose](https://github.com/pressly/goose) v3.27.1 | (shares the goose-migrated schema) |
| Database | PostgreSQL 16.13 | PostgreSQL 16.13 |

**Why Dapper instead of EF Core?** sqlc generates type-safe *raw* SQL executed
over pgx. The closest .NET equivalent is Dapper over Npgsql — a thin micro-ORM
that also executes raw SQL. This keeps the comparison about the runtime + driver
+ framework rather than about ORM query-translation overhead. EF Core would add
change-tracking and LINQ translation that sqlc simply doesn't do, so it would
not be apples-to-apples.

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

For each service we record:

* **Idle** CPU% and RSS (server up, zero traffic, 15s window).
* **Per-scenario under-load** CPU% and RSS, sampled once per second in parallel
  with the load test (`scripts/sample_resources.sh`, reads `/proc/<pid>`).
  CPU% is relative to a single core (100% = one fully-busy core; max 200% here).
* **Throughput** (req/s), **latency** (avg + percentiles), and **error counts**
  from bombardier.

Each scenario runs for **60 seconds** at **256 concurrent connections**.

### Note on the `PUT`/`UPDATE` scenario

bombardier replays one fixed request, so the update scenario hammers a single
row (`/users/1`). Concurrent updates to one row serialize on a Postgres row
lock, so that scenario is dominated by **DB lock contention** (identically for
both apps) rather than framework speed. The `health`, `read`, `list`, and
`create` scenarios are the cleaner framework/runtime comparisons.

## Running it yourself

Prereqts: PostgreSQL running locally with a `bench`/`benchpass` role owning a
`benchdb` database, plus Go, the .NET 10 SDK, `bombardier`, `sqlc`, and `goose`.

```sh
# 1. migrate + generate
goose -dir migrations postgres "$DSN" up
cd go-api && sqlc generate && cd ..

# 2. build both
(cd go-api && go build -o ../bin/go-api .)
(cd dotnet-api && dotnet publish -c Release -o ../bin/dotnet-api)

# 3. run the full benchmark (writes results/raw/**)
DURATION=60 CONNS=256 SEED_ROWS=10000 bash scripts/run_benchmark.sh

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
├── dotnet-api/            # .NET service (Minimal API + Npgsql + Dapper)
├── scripts/
│   ├── seed.sh            # reset + seed the users table
│   ├── sample_resources.sh# per-process CPU/RSS sampler
│   ├── run_benchmark.sh   # orchestrator
│   └── summarize.py       # raw JSON -> results/RESULTS.md
└── results/               # RESULTS.md + raw per-scenario JSON
```
