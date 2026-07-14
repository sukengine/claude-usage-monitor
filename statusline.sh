#!/usr/bin/env bash
# Claude Code statusline — pure grep/sed/awk, NO jq required (works on the
# jq-less claude:v2.1.170 image and the newer public image alike).
#
# Reads the statusLine JSON payload on stdin and renders:
#   ⬢ <instance>  <cwd>  <model> │ session <%> · week <%> │ ctx <used%> (<ctx>/<window>) │
#   tok in:<in> out:<out> cache:<read>+<create> │ $<cost>
#
# Data source = the payload's own fields (context_window / rate_limits / cost);
# no need to run /usage and the transcript is NOT parsed (its format is internal
# & version-dependent). Two DIFFERENT percentages, both labelled:
#   ctx      = context_window.used_percentage — the conversation's context fill
#              (what /context shows; token-based estimate if payload is null)
#   session  = rate_limits.five_hour.used_percentage — the 5-hour quota block
#              that /usage labels "Current session"
#   week     = rate_limits.seven_day.used_percentage — the weekly quota
set -o pipefail
input=$(cat)

# numeric field by key, quote-anchored so "total_input_tokens" ≠ "input_tokens"
gv()  { printf '%s' "$input" | grep -oE "\"$1\":[0-9]+"                | head -1 | grep -oE '[0-9]+'; }
# numeric field nested one level inside a named object: gvo <object> <key>
gvo() { printf '%s' "$input" | grep -oE "\"$1\":\{[^{}]*\"$2\":[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
# string field by key
gs()  { printf '%s' "$input" | grep -oE "\"$1\":\"[^\"]*\""            | head -1 | sed 's/^[^:]*:"//; s/"$//'; }

# Instance name: prefer the CONTAINER_NAME env (set by ./cl / compose); if it is
# not present (e.g. a container started before that wiring existed), fall back to
# the Remote Control session prefix in PID1's cmdline (…-prefix horizon-<name>).
NAME="${CONTAINER_NAME:-}"
if [ -z "$NAME" ] && [ -r /proc/1/cmdline ]; then
  NAME=$(tr '\0' '\n' < /proc/1/cmdline | grep -m1 '^horizon-' | sed 's/^horizon-//')
fi

# Current folder: workspace.current_dir (fallback: top-level cwd), $HOME -> ~
CWD=$(gs current_dir); [ -z "$CWD" ] && CWD=$(gs cwd)
CWD=$(printf '%s' "$CWD" | sed "s#^${HOME:-/home/agent}#~#")

MODEL=$(gs display_name)
SIZE=$(gv context_window_size)
IN=$(gv input_tokens);  OUT=$(gv output_tokens)
CC=$(gv cache_creation_input_tokens); CR=$(gv cache_read_input_tokens)
FIVE=$(gvo five_hour used_percentage); SEVEN=$(gvo seven_day used_percentage)
# resets_at (epoch) per window — used to detect a STALE snapshot: the payload's
# rate_limits is the last API response, so after a window rolls over an idle
# session keeps showing the pre-reset %. If resets_at is already in the past the
# window has reset → treat as 0% (matches /usage).
R5=$(printf '%s' "$input" | grep -oE '"five_hour":\{[^{}]*"resets_at":[0-9]+' | grep -oE '[0-9]+$')
R7=$(printf '%s' "$input" | grep -oE '"seven_day":\{[^{}]*"resets_at":[0-9]+' | grep -oE '[0-9]+$')
NOW=$(date +%s 2>/dev/null || echo 0)
COST=$(printf '%s' "$input" | grep -oE '"total_cost_usd":[0-9.]+' | head -1 | sed 's/.*://')

# Context "% used": context_window.used_percentage — the same number /usage shows.
# Only context_window carries used_percentage BEFORE rate_limits in the payload,
# so cut rate_limits off first to disambiguate. May be null on an idle session.
UPCT=$(printf '%s' "$input" | sed 's/"rate_limits".*//' | grep -oE '"used_percentage":[0-9.]+' | head -1 | sed 's/.*://')

# --- X = ค่าจริงจาก Upstash (get-usage push) → เลขหลัก ; payload = ในวงเล็บ (Y) ---
# ดึงผ่าน wget (image ไม่มี curl), cache 60s => อัปเดต ~ทุก 1 นาที. statusline ถูกเรียก
# เฉพาะตอนมี client เรนเดอร์ (attach) ดังนั้น detach = หยุดดึงเอง ไม่ต้อง detect เพิ่ม.
UPSTASH_URL="${UPSTASH_URL:-https://liked-marlin-151530.upstash.io}"
UPSTASH_READ_TOKEN="${UPSTASH_READ_TOKEN:-YOUR_UPSTASH_READONLY_TOKEN}"
UCACHE="${TMPDIR:-/tmp}/cc-usage.cache"
XSESS=""; XWEEK=""
# fetch ผ่าน curl หรือ wget (แล้วแต่ image ไหนมี — m1=wget, m77=curl)
_ccfetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -m 6 -H "Authorization: Bearer $UPSTASH_READ_TOKEN" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=6 --header="Authorization: Bearer $UPSTASH_READ_TOKEN" "$1"
  fi
}
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
  # refetch หนึ่งครั้งต่อสล็อต 5 นาที โดยขอบสล็อตเลื่อน +30s => :00:30, :05:30, :10:30 …
  # (writer get-usage.sh รัน */5 ที่ :00/:05 ใช้เวลา ~5s ดังนั้น +30s รับประกันได้ค่าที่ push แล้ว)
  now=$(date +%s)
  cur_slot=$(( (now - 30) / 300 ))
  mt=$(stat -c %Y "$UCACHE" 2>/dev/null || echo 0)
  cache_slot=$(( (mt - 30) / 300 ))
  if [ ! -s "$UCACHE" ] || [ "$cur_slot" != "$cache_slot" ]; then
    r=$(_ccfetch "$UPSTASH_URL/get/claude:usage" 2>/dev/null)
    [ -n "$r" ] && printf '%s' "$r" > "$UCACHE"
  fi
  u=$(cat "$UCACHE" 2>/dev/null)
  # ค่าถูกห่อเป็น JSON escaped ("{\"session_pct\":11,...}") จึง match แบบข้าม \": punctuation
  XSESS=$(printf '%s' "$u" | grep -oE 'session_pct[^0-9]+[0-9]+' | grep -oE '[0-9]+' | head -1)
  XWEEK=$(printf '%s' "$u" | grep -oE 'week_pct[^0-9]+[0-9]+'    | grep -oE '[0-9]+' | head -1)
fi

awk -v name="${NAME:-}" -v cwd="${CWD:-}" -v model="${MODEL:-?}" -v size="${SIZE:-0}" \
    -v in_t="${IN:-0}" -v out_t="${OUT:-0}" -v cc="${CC:-0}" -v cr="${CR:-0}" \
    -v five="${FIVE:-0}" -v seven="${SEVEN:-0}" -v cost="${COST:-0}" -v upct="${UPCT:-}" \
    -v xsess="${XSESS:-}" -v xweek="${XWEEK:-}" \
    -v r5="${R5:-0}" -v r7="${R7:-0}" -v now="${NOW:-0}" \
    -v HEX="⬢" -v SEP=" │ " -v DOT=" · " '
function hn(n){ if(n>=1000000) return sprintf("%.1fM",n/1000000);
               else if(n>=1000) return sprintf("%.1fk",n/1000);
               else            return sprintf("%d",n); }
BEGIN{
  R="\033[0m"; CY="\033[01;36m"; BL="\033[01;34m"; DM="\033[02m";
  GN="\033[32m"; YE="\033[33m"; RE="\033[31m";
  # A window whose resets_at is already in the past has rolled over; the stale
  # snapshot still shows the pre-reset %, so force it to 0 (matches /usage).
  if(r5+0>0 && now+0>0 && r5+0<=now+0) five=0;
  if(r7+0>0 && now+0>0 && r7+0<=now+0) seven=0;
  ctx = in_t + cc + cr;                                   # tokens occupying context
  pct = (upct!="") ? upct+0 : ((size>0)? ctx*100.0/size : 0);   # prefer payload %
  cpc = (pct>=80)?RE : (pct>=50)?YE : GN;                 # color by pressure
  c5  = (five>=80)?RE : (five>=50)?YE : GN;
  c7  = (seven>=80)?RE : (seven>=50)?YE : GN;
  s="";
  if(name!="") s = s CY HEX " " name R "  ";
  if(cwd!="")  s = s BL cwd R "  ";
  s = s DM model R;
  # payload (Y) = เลขหลัก, X (Upstash) = ในวงเล็บเหลี่ยม; ไม่มี X → payload เดี่ยว
  sess_s = (xsess!="") ? sprintf("session %d%% [%d%%]", five, xsess)  : sprintf("session %d%%", five);
  week_s = (xweek!="") ? sprintf("week %d%% [%d%%]",   seven, xweek) : sprintf("week %d%%",   seven);
  cv5 = (xsess!="") ? xsess+0 : five+0;  c5 = (cv5>=80)?RE : (cv5>=50)?YE : GN;
  cv7 = (xweek!="") ? xweek+0 : seven+0; c7 = (cv7>=80)?RE : (cv7>=50)?YE : GN;
  s = s DM SEP R c5 sess_s R DM DOT R c7 week_s R;
  s = s DM SEP R cpc sprintf("ctx %.0f%%", pct) R DM sprintf(" (%s/%s)", hn(ctx), hn(size)) R;
  s = s DM SEP R sprintf("tok in:%s out:%s cache:%s+%s", hn(in_t), hn(out_t), hn(cr), hn(cc));
  s = s DM SEP R sprintf("$%.4f", cost);
  printf "%s", s;
}'
