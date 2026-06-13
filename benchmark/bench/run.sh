#!/usr/bin/env bash
# Go vs .NET CRUD benchmark orchestrator.
#
# For each app it:
#   1. (re)seeds an identical dataset into that app's database,
#   2. continuously records idle CPU/memory of the container,
#   3. runs bombardier against each CRUD scenario for DURATION seconds while
#      continuously recording CPU/memory of BOTH the app and Postgres.
#
# Resource usage is sampled via the Docker API (bench/sampler.py) every INTERVAL
# seconds, so the full time series is preserved as CSV in bench/results/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
cd "$BENCH_DIR"

# ---- Tunables -------------------------------------------------------------
DURATION="${DURATION:-120s}"
CONNECTIONS="${CONNECTIONS:-256}"
TIMEOUT="${TIMEOUT:-10s}"
SEED_ROWS="${SEED_ROWS:-1000}"
WARMUP="${WARMUP:-8s}"
INTERVAL="${INTERVAL:-0.5}"     # resource sampling interval (seconds)
IDLE_SECS="${IDLE_SECS:-15}"    # idle recording window (seconds)
TARGET_ID="${TARGET_ID:-500}"   # an id guaranteed to exist after seeding

POST_BODY='{"name":"Bench User","email":"bench@example.com","age":30}'
PUT_BODY='{"name":"Updated User","email":"updated@example.com","age":42}'

# app key | host port | compose service | database name
APPS=(
  "go|8081|go-app|bench_go"
  "dotnet|8082|dotnet-app|bench_dotnet"
)

# scenario key | method | path | body
SCENARIOS=(
  "health|GET|/health|"
  "read_one|GET|/users/${TARGET_ID}|"
  "list|GET|/users?limit=20&offset=0|"
  "update|PUT|/users/${TARGET_ID}|${PUT_BODY}"
  "create|POST|/users|${POST_BODY}"
)

mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR"/*.json "$RESULTS_DIR"/*.csv 2>/dev/null || true

cat > "$RESULTS_DIR/_meta.json" <<META
{
  "duration": "$DURATION",
  "connections": $CONNECTIONS,
  "timeout": "$TIMEOUT",
  "seed_rows": $SEED_ROWS,
  "sample_interval_s": $INTERVAL,
  "app_cpus": "${APP_CPUS:-1.5}",
  "app_mem": "${APP_MEM:-1g}",
  "db_cpus": "${DB_CPUS:-1.5}",
  "db_mem": "${DB_MEM:-1g}",
  "host_cpus": $(nproc),
  "dotnet_mode": "Native AOT + raw Npgsql",
  "go_mode": "compiled + sqlc/pgx"
}
META

cid() { docker compose ps -q "$1"; }
PG_CID="$(cid postgres)"

seed_db() {
  local db="$1"
  docker compose exec -T postgres psql -q -U bench -d "$db" >/dev/null <<SQL
TRUNCATE users RESTART IDENTITY;
INSERT INTO users (name, email, age)
SELECT 'User ' || g, 'user' || g || '@example.com', (g % 80) + 18
FROM generate_series(1, ${SEED_ROWS}) g;
SQL
}

start_sampler() { # container out -> echoes pid
  # stdout/stderr -> /dev/null so the backgrounded process does not hold the
  # command-substitution pipe open (the sampler writes its CSV to a file).
  python3 "$SCRIPT_DIR/sampler.py" "$1" "$2" "$INTERVAL" >/dev/null 2>&1 &
  echo $!
}
stop_sampler() { kill -TERM "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }

measure_idle() {
  local container="$1" out="$2"
  local p; p=$(start_sampler "$container" "$out")
  sleep "$IDLE_SECS"
  stop_sampler "$p"
}

run_scenario() {
  local app="$1" port="$2" container="$3" skey="$4" method="$5" path="$6" body="$7"
  local url="http://localhost:${port}${path}"
  local json="$RESULTS_DIR/${app}_${skey}.json"

  echo "  -> [$app] $skey ($method $path)  for $DURATION @ $CONNECTIONS conns"

  local bargs=(-c "$CONNECTIONS" -d "$DURATION" -t "$TIMEOUT" -l -m "$method" -o json -p result)
  if [ -n "$body" ]; then
    bargs+=(-H "Content-Type: application/json" -b "$body")
  fi

  # warmup (not measured)
  bombardier -c "$CONNECTIONS" -d "$WARMUP" -t "$TIMEOUT" -m "$method" \
    ${body:+-H "Content-Type: application/json" -b "$body"} -q "$url" >/dev/null 2>&1 || true

  local sp dp
  sp=$(start_sampler "$container" "$RESULTS_DIR/${app}_${skey}_stats.csv")
  dp=$(start_sampler "$PG_CID" "$RESULTS_DIR/${app}_${skey}_db_stats.csv")

  bombardier "${bargs[@]}" "$url" > "$json" 2>/dev/null || true

  stop_sampler "$sp"
  stop_sampler "$dp"
}

echo "=============================================="
echo " Benchmark config"
echo "   duration=$DURATION connections=$CONNECTIONS seed_rows=$SEED_ROWS sample=${INTERVAL}s"
echo "   app limits: ${APP_CPUS:-1.5} vCPU / ${APP_MEM:-1g}"
echo "=============================================="

for entry in "${APPS[@]}"; do
  IFS='|' read -r app port svc db <<< "$entry"
  container="$(cid "$svc")"
  echo ""
  echo "### App: $app (service=$svc port=$port db=$db container=${container:0:12})"

  echo "  seeding $SEED_ROWS rows into $db ..."
  seed_db "$db"

  echo "  recording idle resource usage (${IDLE_SECS}s) ..."
  sleep 2
  measure_idle "$container" "$RESULTS_DIR/${app}_idle_stats.csv"

  for s in "${SCENARIOS[@]}"; do
    IFS='|' read -r skey method path body <<< "$s"
    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
      seed_db "$db"
    fi
    run_scenario "$app" "$port" "$container" "$skey" "$method" "$path" "$body"
  done
done

echo ""
echo "All scenarios complete. Generating report ..."
python3 "$SCRIPT_DIR/report.py" "$RESULTS_DIR" | tee "$RESULTS_DIR/REPORT.md"
