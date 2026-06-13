# Go vs .NET — CRUD Benchmark

A head-to-head benchmark of two functionally identical CRUD REST APIs built on
each ecosystem's idiomatic, latest-stable stack, run under **equal CPU and
memory limits** against a **shared Postgres** instance.

## Stacks

| Concern      | Go app (`go-app/`)                  | .NET app (`dotnet-app/`)                 |
|--------------|-------------------------------------|------------------------------------------|
| Language/RT  | Go 1.26 (compiled)                  | .NET 10, **Native AOT** (ASP.NET Core)   |
| HTTP router  | [chi](https://github.com/go-chi/chi) v5 | Minimal APIs (`CreateSlimBuilder`)   |
| DB driver    | [pgx](https://github.com/jackc/pgx) v5 (pool) | [Npgsql](https://www.npgsql.org) 10 (`NpgsqlDataSource`, auto-prepare) |
| Data access  | [sqlc](https://sqlc.dev) (typed, raw SQL) | raw typed `Npgsql` commands          |
| Migrations   | [goose](https://github.com/pressly/goose) v3 | SQL migration runner (goose analog) |
| JSON         | encoding/json                       | System.Text.Json **source-generated**    |
| GC/runtime   | cgroup-aware GOMAXPROCS (Go 1.25+)  | Server GC, no JIT (AOT)                   |
| Database     | PostgreSQL 17                       | PostgreSQL 17                            |

All versions are the latest stable available at the time of writing.

### Optimizations applied

**.NET (best-practice high-performance path):**

- **Native AOT** (`<PublishAot>`) — compiles to a self-contained native binary,
  no JIT, trimmed runtime. Runs on the minimal `runtime-deps` base image.
- **Source-generated JSON** (`JsonSerializerContext`) — required for AOT and
  faster than reflection-based serialization.
- **Slim host** (`WebApplication.CreateSlimBuilder`) — minimal middleware/config.
- **Raw `Npgsql`** via `NpgsqlDataSource` with `MaxAutoPrepare` (server-side
  prepared-statement caching) — no ORM overhead.
- Server GC, `InvariantGlobalization`, `OptimizationPreference=Speed`.

**Go** is already a compiled binary with a cgroup-aware runtime (Go 1.25+
auto-sizes `GOMAXPROCS` to the CPU limit), pooled `pgx`, and prepared-statement
caching — so it serves as the lean baseline and is kept idiomatic.

### A note on fairness

Both apps now use a **raw, typed-SQL** data layer (`sqlc`+`pgx` vs hand-written
`Npgsql` commands), so this is a close apples-to-apples comparison rather than
ORM-vs-sqlc. Schemas, queries, JSON contract (verified byte-identical), and
connection-pool sizes (10/30) all match.

> An earlier revision used EF Core (a full ORM) on the .NET side; those results
> live in git history. EF Core's query pipeline is not Native-AOT compatible,
> which is why the optimized build moved to raw Npgsql.

Both services:

- expose the identical REST contract and JSON shape (verified),
- use a connection pool with the same min/max sizes (10 / 30),
- run migrations at startup,
- each own a separate database (`bench_go` / `bench_dotnet`) inside the **same**
  Postgres container so engine and resources are identical. Apps are
  load-tested **sequentially**, so only one is under load at a time.

## Equal resources

Set in `docker-compose.yml` (override via env):

| Container   | CPU (`APP_CPUS`/`DB_CPUS`) | Memory (`APP_MEM`/`DB_MEM`) |
|-------------|----------------------------|------------------------------|
| go-app      | 1.5 vCPU                   | 1 GiB                        |
| dotnet-app  | 1.5 vCPU                   | 1 GiB                        |
| postgres    | 1.5 vCPU                   | 1 GiB                        |

Limits are enforced via cgroup CPU quota + memory limit. The load generator
([bombardier](https://github.com/codesenberg/bombardier)) runs on the host so
it doesn't steal the apps' budget; because both apps face identical conditions
the comparison is fair. During the runs the apps saturate their CPU cap, which
confirms the application (not the generator or DB) is the bottleneck.

## REST API (both apps)

| Method | Path           | Description        |
|--------|----------------|--------------------|
| GET    | `/health`      | Liveness (no DB)   |
| POST   | `/users`       | Create             |
| GET    | `/users/{id}`  | Read one           |
| GET    | `/users`       | List (limit/offset)|
| PUT    | `/users/{id}`  | Update             |
| DELETE | `/users/{id}`  | Delete             |

## Benchmark scenarios

Each runs for `DURATION` (default 120s) at `CONNECTIONS` concurrency (default
256), preceded by a short un-measured warmup. Mutating scenarios reseed the
dataset first so both apps start from an identical state.

1. `GET /health` — pure HTTP throughput, no DB
2. `GET /users/{id}` — point read
3. `GET /users?limit=20` — list query
4. `PUT /users/{id}` — update
5. `POST /users` — insert

For each scenario the harness records throughput (req/s), latency
(mean/p99/max) and status-code counts (via bombardier), plus a **continuous
time series** of CPU% and memory for **both the app and the Postgres
container** — sampled every `INTERVAL` seconds (default 0.5s) straight from the
Docker Engine API by `bench/sampler.py`. A separate **idle** measurement is
recorded per app. The full per-sample series is kept as CSV in
`bench/results/` alongside the report.

## Running it

Prerequisites: Docker + Docker Compose, Go (to compile the static binary),
`bombardier`, `jq`, `python3`.

```sh
cd benchmark

# 1. build the Go binary (static) + both images
( cd go-app && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o benchapp . )
docker compose build

# 2. start the stack
docker compose up -d

# 3. run the benchmark (writes bench/results/REPORT.md)
DURATION=60s CONNECTIONS=256 bash bench/run.sh

# 4. tear down
docker compose down -v
```

Tunables (env vars): `DURATION`, `CONNECTIONS`, `TIMEOUT`, `SEED_ROWS`,
`WARMUP`, `INTERVAL`, `IDLE_SECS`, `APP_CPUS`, `APP_MEM`, `DB_CPUS`, `DB_MEM`.

## Results

The generated report lands in [`bench/results/REPORT.md`](bench/results/REPORT.md).
Alongside it: raw bombardier JSON per scenario, and the full per-sample CPU/memory
time series as CSV — `<app>_<scenario>_stats.csv` (the app) and
`<app>_<scenario>_db_stats.csv` (Postgres), plus `<app>_idle_stats.csv`.

## Regenerating generated code

- sqlc (Go queries): `cd go-app && sqlc generate`
- .NET migrations are plain SQL in `dotnet-app/Migrations.cs`, applied at startup.

## Notes on the environment

The build trusts a transparent egress-proxy CA (`certs/`) so NuGet restore over
TLS works inside the .NET build container. The Go binary is compiled on the host
and packaged into a minimal Alpine image (no outbound TLS needed at runtime).
