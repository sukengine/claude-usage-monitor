#!/bin/bash
# Sustained polling test: ยิง probe ทุก INTERVAL วินาที นานสุด DURATION วินาที
# หยุดทันทีถ้าเจอ throttle (rate limited หรือแถบ Fable หาย)
# usage: sustain-test.sh <interval_sec> <duration_sec> <tag>
DIR=/home/sukkarin/work/ai-agent-workspace-m1/claude-usage
INTERVAL=${1:-120}
DURATION=${2:-900}
TAG=${3:-test}
LOG="$DIR/rate-probe.log"

echo ">>> START $TAG : interval=${INTERVAL}s duration=${DURATION}s" | tee -a "$LOG"
END=$(( $(date +%s) + DURATION ))
n=0
result="SURVIVED"
while [ "$(date +%s)" -lt "$END" ]; do
  n=$((n+1))
  "$DIR/probe.sh" "$TAG #$n" >/dev/null
  last=$(tail -1 "$LOG")
  echo "  $last"
  if echo "$last" | grep -q 'RATE_LIMITED' || echo "$last" | grep -q 'fable=\[\]'; then
    result="THROTTLED@probe#$n"
    break
  fi
  # เว้นให้ครบ interval (probe ใช้เวลาภายใน ~3s)
  [ "$(date +%s)" -lt "$END" ] && sleep $(( INTERVAL > 3 ? INTERVAL - 3 : INTERVAL ))
done
echo ">>> RESULT $TAG : $result after $n probes" | tee -a "$LOG"
