#!/usr/bin/env bash
# Orchestrates the full benchmark for both apps under identical conditions.
#
# Methodology:
#   * Both apps are pinned to the same CPU cores (APP_CORES) and given the
#     same DB connection pool; bombardier (the load generator) is pinned to a
#     separate set of cores (LOAD_CORES) so it does not steal the app's CPU.
#   * Apps are benchmarked sequentially (never at the same time) so neither
#     competes with the other for Postgres or memory.
#   * The DB is reset to an identical seed before each app's run.
#   * For every app we record idle CPU/RSS (server up, no traffic) and, for
#     each scenario, under-load CPU/RSS sampled in parallel with bombardier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
SCRIPTS="$ROOT/scripts"
RESULTS="$ROOT/results/raw"

DURATION="${DURATION:-60}"      # seconds per scenario
CONNS="${CONNS:-256}"           # concurrent connections (parallelism)
SEED_ROWS="${SEED_ROWS:-10000}"
APP_CORES="${APP_CORES:-0,1}"
LOAD_CORES="${LOAD_CORES:-2,3}"
IDLE_SECS="${IDLE_SECS:-15}"
WARMUP_SECS="${WARMUP_SECS:-8}"

export PATH="$PATH:/root/go/bin:/usr/share/dotnet"
export DATABASE_URL_GO="postgres://bench:benchpass@127.0.0.1:5432/benchdb?sslmode=disable"
export DATABASE_URL_NET="Host=127.0.0.1;Port=5432;Database=benchdb;Username=bench;Password=benchpass"

BODY='{"name":"Jane Doe","email":"jane@example.com","age":33}'

# scenario := "name|METHOD|path"
SCENARIOS=(
  "health|GET|/health"
  "read_one|GET|/users/1"
  "list_20|GET|/users?limit=20"
  "list_100|GET|/users?limit=100"
  "update|PUT|/users/1"
  "create|POST|/users"
  "delete|DELETE|/users/1"
)

wait_health() {
  local base="$1" tries=0
  until curl -fsS "${base}/health" >/dev/null 2>&1; do
    tries=$((tries+1))
    [ "$tries" -gt 100 ] && { echo "app did not become healthy"; return 1; }
    sleep 0.2
  done
}

run_app() {
  local app="$1" port base pid outdir
  outdir="$RESULTS/$app"
  mkdir -p "$outdir"

  echo "==================== $app ===================="
  bash "$SCRIPTS/seed.sh" "$SEED_ROWS"

  if [ "$app" = "go" ]; then
    port=8080
    GOMAXPROCS=2 DATABASE_URL="$DATABASE_URL_GO" PORT="$port" \
      taskset -c "$APP_CORES" "$BIN/go-api" >"$outdir/server.log" 2>&1 &
    pid=$!
  else
    port=8081
    DOTNET_gcServer=1 DATABASE_URL="$DATABASE_URL_NET" PORT="$port" \
      taskset -c "$APP_CORES" "$BIN/dotnet-api/DotnetApi" >"$outdir/server.log" 2>&1 &
    pid=$!
  fi
  base="http://127.0.0.1:$port"
  echo "$app started pid=$pid on cores $APP_CORES, port $port"

  if ! wait_health "$base"; then
    cat "$outdir/server.log"; kill "$pid" 2>/dev/null || true; return 1
  fi

  # Warmup (JIT for .NET, pool fill, page cache) - not recorded.
  taskset -c "$LOAD_CORES" bombardier -c "$CONNS" -d "${WARMUP_SECS}s" "$base/users?limit=20" >/dev/null 2>&1 || true

  # Idle resource usage: server up, no traffic.
  echo "  sampling idle resources for ${IDLE_SECS}s..."
  bash "$SCRIPTS/sample_resources.sh" "$pid" "$IDLE_SECS" "$outdir/idle.resources.json"
  cat "$outdir/idle.resources.json"; echo

  for entry in "${SCENARIOS[@]}"; do
    IFS='|' read -r name method path <<< "$entry"
    echo "  scenario: $name ($method $path)"
    bash "$SCRIPTS/sample_resources.sh" "$pid" "$DURATION" "$outdir/${name}.resources.json" &
    local sampler=$!

    local args=(-c "$CONNS" -d "${DURATION}s" -l --format json -m "$method")
    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
      args+=(-H 'Content-Type: application/json' -b "$BODY")
    fi
    taskset -c "$LOAD_CORES" bombardier "${args[@]}" "$base$path" >"$outdir/${name}.bombardier.json" 2>"$outdir/${name}.bombardier.err" || \
      echo "    bombardier returned non-zero (see ${name}.bombardier.err)"
    wait "$sampler"
    cat "$outdir/${name}.resources.json"; echo
  done

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "$app stopped"
}

mkdir -p "$RESULTS"
run_app go
run_app dotnet
echo "ALL DONE"
