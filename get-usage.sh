#!/bin/bash
# ดึง /usage แล้วสกัด session / week (all models) / week (Fable) ลง usage.txt
# รูปแบบ key=value; ถ้าไม่มีบรรทัด Fable (โดน rate limit/render ไม่ครบ) => fable=rate_limited

SESSION_NAME="claude-usage.1"
DIR="/home/sukkarin/work/ai-agent-workspace-m1/claude-usage"
OUTPUT_TMP="$DIR/output.txt"
USAGE_FILE="$DIR/usage.txt"

# โหลด secrets (Upstash write token ฯลฯ) — cron ไม่ source .env ให้เอง
[ -f "$DIR/.env" ] && set -a && . "$DIR/.env" && set +a

# 1. เคลียร์ input ที่อาจค้าง (remote-control/manual mode บางทีไม่ submit) แล้วส่ง /usage
tmux send-keys -t "$SESSION_NAME" C-u
sleep 1
tmux send-keys -t "$SESSION_NAME" "/usage"
sleep 1
tmux send-keys -t "$SESSION_NAME" Enter
sleep 4
# 2. จับภาพหน้าจอ
tmux capture-pane -S -160 -pt "$SESSION_NAME" > "$OUTPUT_TMP"
# 3. ปิดหน้าสถิติ
tmux send-keys -t "$SESSION_NAME" Escape

# 4. สกัดตัวเลข % จากบรรทัด label ที่ระบุ (คืนเฉพาะตัวเลข)
extract() {
  grep -A1 -E "$1" "$OUTPUT_TMP" | grep -oE '[0-9]+% used' | grep -oE '[0-9]+' | head -1
}

SESSION=$(extract 'Current session')
WEEK=$(extract 'Current week \(all models\)')
FABLE=$(extract 'Current week \(Fable\)')
# เผื่อชื่อโมเดลเปลี่ยน: บรรทัด weekly ใด ๆ ที่ไม่ใช่ (all models)
if [ -z "$FABLE" ]; then
  FABLE=$(grep -A1 -P 'Current week \((?!all models)' "$OUTPUT_TMP" 2>/dev/null \
          | grep -oE '[0-9]+% used' | grep -oE '[0-9]+' | head -1)
fi

# ถ้า session และ week ว่างทั้งคู่ = /usage dialog ไม่ render (session busy/ค้าง)
# อย่าเขียนทับค่าเดิมด้วย null — ข้ามรอบนี้
if [ -z "$SESSION" ] && [ -z "$WEEK" ]; then
  echo "warn: /usage did not render (session/week empty) — keep previous value, skip"
  exit 0
fi

# มี session/week แต่ไม่มีบรรทัด Fable = per-model โดน rate limit
[ -z "$FABLE" ] && FABLE="rate_limited"

# 5. เขียนแบบ key=value (truncate in-place, container เห็นค่าใหม่ทันที)
{
  echo "session=${SESSION:-}"
  echo "week=${WEEK:-}"
  echo "fable=${FABLE}"
} > "$USAGE_FILE"

# 6. push JSON ขึ้น Upstash (push model — ไม่ต้องเปิด server ออก public)
if [ -n "$UPSTASH_REDIS_REST_URL" ] && [ -n "$UPSTASH_WRITE_TOKEN" ]; then
  TS=$(TZ='Asia/Bangkok' date -Iseconds)
  if [ "$FABLE" = "rate_limited" ]; then
    FJSON='"fable_pct":null,"fable_status":"rate_limited"'
  else
    FJSON="\"fable_pct\":${FABLE},\"fable_status\":\"ok\""
  fi
  JSON="{\"session_pct\":${SESSION:-null},\"week_pct\":${WEEK:-null},${FJSON},\"updated\":\"${TS}\"}"
  curl -s -X POST "$UPSTASH_REDIS_REST_URL/set/claude:usage" \
       -H "Authorization: Bearer $UPSTASH_WRITE_TOKEN" \
       --data-raw "$JSON" >/dev/null && PUSH="ok" || PUSH="fail"
else
  PUSH="skipped (no upstash env)"
fi

echo "saved: session=${SESSION:-?} week=${WEEK:-?} fable=${FABLE} | upstash=$PUSH"
