#!/usr/bin/env bash
# Continuously record CPU and memory once per second for the whole lifetime of
# the app process, tagging each sample with the current benchmark phase.
#
# Usage: sample_continuous.sh <pid> <phase_file> <out_csv>
#
# Columns: epoch, elapsed_s, phase, app_cpu_pct, app_rss_mib, sys_cpu_pct
#   * app_cpu_pct  CPU of the app process relative to a single core
#                  (100% == one fully-busy core).
#   * app_rss_mib  resident memory of the app process (MiB).
#   * sys_cpu_pct  whole-machine CPU busy %, 0-100 across all cores.
# Samples until the app process exits, so it captures idle, warmup, every
# scenario, and the gaps in between -- i.e. all CPU/memory during the test.
set -uo pipefail
pid="$1"; phase_file="$2"; out="$3"
clk=$(getconf CLK_TCK)

read_app_cpu() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null; }
read_app_rss() { awk '/^VmRSS:/{print $2}' "/proc/$1/status" 2>/dev/null; }
read_sys()     { awk '/^cpu /{idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print total" "idle}' /proc/stat; }

echo "epoch,elapsed_s,phase,app_cpu_pct,app_rss_mib,sys_cpu_pct" > "$out"

start=$(date +%s)
prev_app=$(read_app_cpu "$pid"); [ -z "${prev_app:-}" ] && prev_app=0
read prev_tot prev_idle < <(read_sys)

while [ -d "/proc/$pid" ]; do
  sleep 1
  cur_app=$(read_app_cpu "$pid"); [ -z "${cur_app:-}" ] && break
  rss_kb=$(read_app_rss "$pid"); [ -z "${rss_kb:-}" ] && rss_kb=0
  read cur_tot cur_idle < <(read_sys)

  d_app=$(( cur_app - prev_app )); prev_app=$cur_app
  d_tot=$(( cur_tot - prev_tot )); d_idle=$(( cur_idle - prev_idle ))
  prev_tot=$cur_tot; prev_idle=$cur_idle

  app_cpu=$(awk -v d="$d_app" -v c="$clk" 'BEGIN{printf "%.2f", (d*100.0)/c}')
  app_rss=$(awk -v k="$rss_kb" 'BEGIN{printf "%.2f", k/1024.0}')
  sys_cpu=$(awk -v t="$d_tot" -v i="$d_idle" 'BEGIN{printf "%.2f", (t>0)?(100.0*(t-i)/t):0}')
  phase=$(cat "$phase_file" 2>/dev/null || echo "?")
  now=$(date +%s)
  echo "${now},$(( now - start )),${phase},${app_cpu},${app_rss},${sys_cpu}" >> "$out"
done
