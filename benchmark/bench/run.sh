#!/usr/bin/env bash
# Go vs .NET CRUD benchmark orchestrator.
#
# For each app it:
#   1. (re)seeds an identical dataset into that app's database,
#   2. records idle CPU/memory of the container,
#   3. runs bombardier against each CRUD scenario for DURATION seconds while
#      sampling the container's CPU/memory under load.
#
# Results land in bench/results/ as JSON (bombardier) + CSV (docker stats).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
cd "$BENCH_DIR"

# ---- Tunables -------------------------------------------------------------
DURATION="${DURATION:-60s}"
CONNECTIONS="${CONNECTIONS:-256}"
TIMEOUT="${TIMEOUT:-10s}"
SEED_ROWS="${SEED_ROWS:-1000}"
WARMUP="${WARMUP:-5s}"
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
  "app_cpus": "${APP_CPUS:-1.5}",
  "app_mem": "${APP_MEM:-1g}",
  "db_cpus": "${DB_CPUS:-1.5}",
  "db_mem": "${DB_MEM:-1g}",
  "host_cpus": $(nproc)
}
META

cid() { docker compose ps -q "$1"; }

seed_db() {
  local db="$1"
  docker compose exec -T postgres psql -q -U bench -d "$db" >/dev/null <<SQL
TRUNCATE users RESTART IDENTITY;
INSERT INTO users (name, email, age)
SELECT 'User ' || g, 'user' || g || '@example.com', (g % 80) + 18
FROM generate_series(1, ${SEED_ROWS}) g;
SQL
}

# Sample docker stats for a container until a stop-file appears.
sample_stats() {
  local container="$1" out="$2" stop="$3"
  echo "cpu_perc,mem_used_mib" > "$out"
  while [ ! -f "$stop" ]; do
    line=$(docker stats --no-stream --format '{{.CPUPerc}};{{.MemUsage}}' "$container" 2>/dev/null || true)
    if [ -n "$line" ]; then
      cpu=$(echo "$line" | sed 's/%.*//')
      mem=$(echo "$line" | sed 's/.*;//; s#/.*##' | tr -d ' ')
      # normalize mem to MiB
      python3 - "$mem" >>"$out" <<'PY' "$cpu"
import sys
mem=sys.argv[1]; cpu=sys.argv[2]
u=mem.upper()
val=float(''.join(c for c in u if (c.isdigit() or c=='.')) or 0)
if 'GIB' in u: val*=1024
elif 'KIB' in u: val/=1024
elif 'B' in u and 'MIB' not in u and 'GIB' not in u and 'KIB' not in u: val/=1024*1024
print(f"{cpu},{val:.1f}")
PY
    fi
  done
}

measure_idle() {
  local container="$1" out="$2"
  echo "cpu_perc,mem_used_mib" > "$out"
  for _ in 1 2 3 4 5; do
    line=$(docker stats --no-stream --format '{{.CPUPerc}};{{.MemUsage}}' "$container" 2>/dev/null || true)
    cpu=$(echo "$line" | sed 's/%.*//')
    mem=$(echo "$line" | sed 's/.*;//; s#/.*##' | tr -d ' ')
    python3 - "$mem" >>"$out" <<'PY' "$cpu"
import sys
mem=sys.argv[1]; cpu=sys.argv[2]
u=mem.upper()
val=float(''.join(c for c in u if (c.isdigit() or c=='.')) or 0)
if 'GIB' in u: val*=1024
elif 'KIB' in u: val/=1024
print(f"{cpu},{val:.1f}")
PY
  done
}

run_scenario() {
  local app="$1" port="$2" container="$3" skey="$4" method="$5" path="$6" body="$7"
  local url="http://localhost:${port}${path}"
  local json="$RESULTS_DIR/${app}_${skey}.json"
  local stats="$RESULTS_DIR/${app}_${skey}_stats.csv"
  local stop="$RESULTS_DIR/.${app}_${skey}.stop"

  echo "  -> [$app] $skey ($method $path)"

  local bargs=(-c "$CONNECTIONS" -d "$DURATION" -t "$TIMEOUT" -l -m "$method" -o json -p result)
  if [ -n "$body" ]; then
    bargs+=(-H "Content-Type: application/json" -b "$body")
  fi

  # warmup (not measured)
  bombardier -c "$CONNECTIONS" -d "$WARMUP" -t "$TIMEOUT" -m "$method" \
    ${body:+-H "Content-Type: application/json" -b "$body"} -q "$url" >/dev/null 2>&1 || true

  rm -f "$stop"
  sample_stats "$container" "$stats" "$stop" &
  local sampler=$!

  bombardier "${bargs[@]}" "$url" > "$json" 2>/dev/null || true

  touch "$stop"
  wait "$sampler" 2>/dev/null || true
  rm -f "$stop"
}

echo "=============================================="
echo " Benchmark config"
echo "   duration=$DURATION connections=$CONNECTIONS seed_rows=$SEED_ROWS"
echo "   app limits: ${APP_CPUS:-1.5} vCPU / ${APP_MEM:-1g}"
echo "=============================================="

for entry in "${APPS[@]}"; do
  IFS='|' read -r app port svc db <<< "$entry"
  container="$(cid "$svc")"
  echo ""
  echo "### App: $app (service=$svc port=$port db=$db container=${container:0:12})"

  echo "  seeding $SEED_ROWS rows into $db ..."
  seed_db "$db"

  echo "  measuring idle resource usage ..."
  sleep 3
  measure_idle "$container" "$RESULTS_DIR/${app}_idle_stats.csv"

  for s in "${SCENARIOS[@]}"; do
    IFS='|' read -r skey method path body <<< "$s"
    # reseed before mutating scenarios so both apps start from the same state
    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
      seed_db "$db"
    fi
    run_scenario "$app" "$port" "$container" "$skey" "$method" "$path" "$body"
  done
done

echo ""
echo "All scenarios complete. Generating report ..."
python3 "$SCRIPT_DIR/report.py" "$RESULTS_DIR" | tee "$RESULTS_DIR/REPORT.md"
