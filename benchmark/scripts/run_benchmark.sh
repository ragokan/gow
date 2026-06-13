#!/usr/bin/env bash
# Orchestrates the full benchmark for both apps under identical conditions.
#
# Methodology:
#   * Both apps are pinned to the same CPU cores (APP_CORES) and given the same
#     DB connection pool; bombardier (the load generator) is pinned to separate
#     cores (LOAD_CORES) so it never steals the app's CPU.
#   * Apps are benchmarked sequentially (never at the same time).
#   * The DB is reset to an identical seed before each app's run.
#   * A single continuous sampler records app + system CPU and app memory once
#     per second for the entire lifetime of each server (idle, warmup, every
#     scenario, and the gaps), tagged with the current phase. Per-scenario
#     start/end timestamps are recorded so stats can be sliced exactly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
SCRIPTS="$ROOT/scripts"
RESULTS="$ROOT/results/raw"

DURATION="${DURATION:-120}"     # seconds per scenario
CONNS="${CONNS:-256}"           # concurrent connections (parallelism)
SEED_ROWS="${SEED_ROWS:-10000}"
APP_CORES="${APP_CORES:-0,1}"
LOAD_CORES="${LOAD_CORES:-2,3}"
IDLE_SECS="${IDLE_SECS:-20}"
WARMUP_SECS="${WARMUP_SECS:-10}"

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
  local app="$1" port base pid outdir phase_file sampler
  outdir="$RESULTS/$app"
  mkdir -p "$outdir"
  phase_file="$outdir/current_phase"
  echo "boot" > "$phase_file"
  : > "$outdir/phases.csv"
  echo "phase,start_epoch,end_epoch" > "$outdir/phases.csv"

  echo "==================== $app ===================="
  bash "$SCRIPTS/seed.sh" "$SEED_ROWS"

  if [ "$app" = "go" ]; then
    port=8080
    GOMAXPROCS=2 DATABASE_URL="$DATABASE_URL_GO" PORT="$port" \
      taskset -c "$APP_CORES" "$BIN/go-api" >"$outdir/server.log" 2>&1 &
    pid=$!
  else
    port=8081
    DATABASE_URL="$DATABASE_URL_NET" PORT="$port" \
      taskset -c "$APP_CORES" "$BIN/dotnet-api/DotnetApi" >"$outdir/server.log" 2>&1 &
    pid=$!
  fi
  base="http://127.0.0.1:$port"
  echo "$app started pid=$pid on cores $APP_CORES, port $port"

  # Start the continuous, whole-run resource recorder.
  bash "$SCRIPTS/sample_continuous.sh" "$pid" "$phase_file" "$outdir/resources.csv" &
  sampler=$!

  if ! wait_health "$base"; then
    cat "$outdir/server.log"; kill "$pid" "$sampler" 2>/dev/null || true; return 1
  fi

  # Warmup (pool fill, page cache; AOT/native has no JIT warmup) - not recorded.
  echo "warmup" > "$phase_file"
  taskset -c "$LOAD_CORES" bombardier -c "$CONNS" -d "${WARMUP_SECS}s" "$base/users?limit=20" >/dev/null 2>&1 || true

  # Idle window: server up, no traffic.
  echo "idle" > "$phase_file"
  echo "  idle window ${IDLE_SECS}s..."
  local s=$(date +%s); sleep "$IDLE_SECS"; local e=$(date +%s)
  echo "idle,$s,$e" >> "$outdir/phases.csv"

  for entry in "${SCENARIOS[@]}"; do
    IFS='|' read -r name method path <<< "$entry"
    echo "  scenario: $name ($method $path)"
    echo "$name" > "$phase_file"
    local args=(-c "$CONNS" -d "${DURATION}s" -l --format json -m "$method")
    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
      args+=(-H 'Content-Type: application/json' -b "$BODY")
    fi
    s=$(date +%s)
    taskset -c "$LOAD_CORES" bombardier "${args[@]}" "$base$path" \
      >"$outdir/${name}.bombardier.json" 2>"$outdir/${name}.bombardier.err" || \
      echo "    bombardier returned non-zero (see ${name}.bombardier.err)"
    e=$(date +%s)
    echo "${name},$s,$e" >> "$outdir/phases.csv"
    echo "idle_between" > "$phase_file"; sleep 2
  done

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  wait "$sampler" 2>/dev/null || true
  rm -f "$phase_file"
  echo "$app stopped"
}

mkdir -p "$RESULTS"
run_app go
run_app dotnet
echo "ALL DONE"
