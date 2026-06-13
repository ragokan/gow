# Go vs .NET — CRUD Benchmark

A head-to-head benchmark of two functionally identical CRUD REST APIs built on
each ecosystem's idiomatic, latest-stable stack, run under **equal CPU and
memory limits** against a **shared Postgres** instance.

## Stacks

| Concern      | Go app (`go-app/`)                  | .NET app (`dotnet-app/`)                 |
|--------------|-------------------------------------|------------------------------------------|
| Language/RT  | Go 1.26                             | .NET 10 (ASP.NET Core 10)                |
| HTTP router  | [chi](https://github.com/go-chi/chi) v5 | Minimal APIs                         |
| DB driver    | [pgx](https://github.com/jackc/pgx) v5 (pool) | [Npgsql](https://www.npgsql.org) 10 |
| Data access  | [sqlc](https://sqlc.dev) (typed, raw SQL) | [EF Core](https://learn.microsoft.com/ef/core) 10 (ORM) |
| Migrations   | [goose](https://github.com/pressly/goose) v3 | EF Core migrations               |
| Database     | PostgreSQL 17                       | PostgreSQL 17                            |
| JSON         | encoding/json                       | System.Text.Json                         |

All versions are the latest stable available at the time of writing.

### A note on fairness

The HTTP, driver, and migration layers are directly comparable. The **data
access layer differs by design**: `sqlc` generates typed Go from hand-written
SQL (effectively raw queries over `pgx`), while EF Core is a full ORM with
change tracking, LINQ translation, and a materialization pipeline. This is the
realistic, idiomatic choice on each side rather than an artificially matched
micro-benchmark — reads use `AsNoTracking()` and the schemas/queries are
equivalent, but the ORM overhead is part of what's being measured. If you want
an apples-to-apples data layer, swap EF Core for Dapper on the .NET side.

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

Each runs for `DURATION` (default 60s) at `CONNECTIONS` concurrency (default
256), preceded by a short un-measured warmup. Mutating scenarios reseed the
dataset first so both apps start from an identical state.

1. `GET /health` — pure HTTP throughput, no DB
2. `GET /users/{id}` — point read
3. `GET /users?limit=20` — list query
4. `PUT /users/{id}` — update
5. `POST /users` — insert

For each scenario the harness records throughput (req/s), latency
(mean/p99/max), status-code counts, and the container's CPU% / memory **under
load** — plus a separate **idle** measurement per app.

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
`WARMUP`, `APP_CPUS`, `APP_MEM`, `DB_CPUS`, `DB_MEM`.

## Results

The generated report lands in [`bench/results/REPORT.md`](bench/results/REPORT.md),
with raw bombardier JSON and per-scenario `docker stats` CSVs alongside it.

## Regenerating generated code

- sqlc: `cd go-app && sqlc generate`
- EF Core migration: `dotnet ef migrations add <Name>` (in `dotnet-app/`)

## Notes on the environment

The build trusts a transparent egress-proxy CA (`certs/`) so NuGet restore over
TLS works inside the .NET build container. The Go binary is compiled on the host
and packaged into a minimal Alpine image (no outbound TLS needed at runtime).
