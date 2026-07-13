#!/bin/bash
# Rate-limit probe: เปิด /usage ครั้งเดียว แล้วบันทึกว่า per-model breakdown
# กลับมาหรือยัง (rate limited หรือไม่) พร้อม timestamp — ไม่ผูกกับ cron
SESSION="claude-usage.1"
OUT="/home/sukkarin/work/ai-agent-workspace-m1/claude-usage/output.txt"
LOG="/home/sukkarin/work/ai-agent-workspace-m1/claude-usage/rate-probe.log"
TS=$(date '+%Y-%m-%d %H:%M:%S %Z')
NOTE="${1:-}"

tmux send-keys -t "$SESSION" "/usage" C-m
sleep 3
tmux capture-pane -S -160 -pt "$SESSION" > "$OUT"
tmux send-keys -t "$SESSION" Escape

if grep -q 'rate limited' "$OUT"; then
  STATUS="RATE_LIMITED"
elif grep -q 'Current session' "$OUT"; then
  STATUS="OK"
else
  STATUS="UNKNOWN"
fi

# บรรทัด weekly ที่ไม่ใช่ (all models) = Fable/model-specific ถ้ามี
FABLE=$(grep -A1 -P 'Current week \((?!all models)' "$OUT" 2>/dev/null \
        | grep -oE '[0-9]+% used' | head -1)

LINE="$TS | $STATUS | fable=[$FABLE] | $NOTE"
echo "$LINE" >> "$LOG"
echo "$LINE"
