#!/bin/bash
# ดึง /usage แล้วสกัด session / week (all models) / week (Fable) ลง usage.txt
# รูปแบบ key=value; ถ้าไม่มีบรรทัด Fable (โดน rate limit/render ไม่ครบ) => fable=rate_limited

SESSION_NAME="claude-usage.1"
OUTPUT_TMP="/home/sukkarin/work/ai-agent-workspace-m1/claude-usage/output.txt"
USAGE_FILE="/home/sukkarin/work/ai-agent-workspace-m1/claude-usage/usage.txt"

# 1. ส่ง /usage แล้วรอ render
tmux send-keys -t "$SESSION_NAME" "/usage" C-m
sleep 3
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

# ไม่มีบรรทัด Fable = โดน rate limit
[ -z "$FABLE" ] && FABLE="rate_limited"

# 5. เขียนแบบ key=value (truncate in-place, container เห็นค่าใหม่ทันที)
{
  echo "session=${SESSION:-}"
  echo "week=${WEEK:-}"
  echo "fable=${FABLE}"
} > "$USAGE_FILE"

echo "saved: session=${SESSION:-?} week=${WEEK:-?} fable=${FABLE}"
