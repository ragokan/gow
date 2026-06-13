#!/usr/bin/env bash
# Sample a process's CPU and memory usage once per second.
#
# Usage: sample_resources.sh <pid> <duration_sec> <out_json>
#
# CPU% is expressed relative to a single core (100% == one fully-busy core),
# computed from utime+stime deltas in /proc/<pid>/stat. RSS is read from
# /proc/<pid>/status (VmRSS) and reported in MiB. Writes a small JSON summary
# with average and peak values to <out_json>.
set -euo pipefail
pid="$1"; dur="$2"; out="$3"
clk=$(getconf CLK_TCK)

read_cpu() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null; }
read_rss() { awk '/^VmRSS:/{print $2}' "/proc/$1/status" 2>/dev/null; }

samples=0; cpu_sum=0; cpu_max=0; rss_sum=0; rss_max=0
prev=$(read_cpu "$pid"); [ -z "${prev:-}" ] && prev=0

for ((i=0; i<dur; i++)); do
  sleep 1
  cur=$(read_cpu "$pid"); [ -z "${cur:-}" ] && break
  rss_kb=$(read_rss "$pid"); [ -z "${rss_kb:-}" ] && rss_kb=0
  djiff=$(( cur - prev )); prev=$cur
  cpu=$(awk -v d="$djiff" -v c="$clk" 'BEGIN{printf "%.2f", (d*100.0)/c}')
  rss=$(awk -v k="$rss_kb" 'BEGIN{printf "%.2f", k/1024.0}')
  cpu_sum=$(awk -v s="$cpu_sum" -v x="$cpu" 'BEGIN{printf "%.4f", s+x}')
  rss_sum=$(awk -v s="$rss_sum" -v x="$rss" 'BEGIN{printf "%.4f", s+x}')
  cpu_max=$(awk -v m="$cpu_max" -v x="$cpu" 'BEGIN{printf "%.2f", (x>m)?x:m}')
  rss_max=$(awk -v m="$rss_max" -v x="$rss" 'BEGIN{printf "%.2f", (x>m)?x:m}')
  samples=$(( samples + 1 ))
done

cpu_avg=$(awk -v s="$cpu_sum" -v n="$samples" 'BEGIN{printf "%.2f", (n>0)?s/n:0}')
rss_avg=$(awk -v s="$rss_sum" -v n="$samples" 'BEGIN{printf "%.2f", (n>0)?s/n:0}')

cat > "$out" <<JSON
{"samples": ${samples}, "cpu_pct_avg": ${cpu_avg}, "cpu_pct_max": ${cpu_max}, "rss_mib_avg": ${rss_avg}, "rss_mib_max": ${rss_max}}
JSON
