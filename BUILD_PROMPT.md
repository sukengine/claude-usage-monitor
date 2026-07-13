# Build prompt — Claude usage monitor stack

A single prompt to hand to Claude Code to build this project end-to-end. The **primary**
delivery is the Upstash push model (no public exposure); the Docker + Cloudflare Tunnel
path is an optional backup.

---

Build a "Claude usage" monitoring stack on this Linux host that shows my Claude Code usage
(session / weekly / Fable %) on an iPhone Scriptable widget, using a free cloud key-value
store so nothing on my host has to be exposed. Work in `./claude-usage`. Implement each
part and verify it before moving on.

## 1. Data collector (get-usage.sh)
There is a long-running tmux session (name: `claude-usage.1`) with `claude` open.
Write `get-usage.sh` that:
- sends `/usage` + Enter to the tmux session, waits ~3s for render, captures the pane to
  `output.txt`, then sends Escape,
- parses three limit bars by label and extracts the integer percent of each:
    - `Current session`            -> session
    - `Current week (all models)`  -> week
    - `Current week (Fable)`       -> fable   (fallback: any `Current week (...)` line
                                               that is NOT `(all models)`)
- if the Fable line is missing (per-model section rate-limited / not rendered), treat
  fable as `rate_limited` (not a number),
- writes `usage.txt` in key=value form (`session=`/`week=`/`fable=`), truncating in place,
- then PUSHES the result to Upstash (see part 2).
- loads `./.env` at the top (cron does not source it): `set -a; . ./.env; set +a`.
- use absolute paths (define a `DIR` var).

## 2. Upstash (primary delivery — no inbound exposure)
Use a free Upstash Redis database (REST API). The collector only makes an OUTBOUND POST;
the widget reads the value back. Two tokens:
- a **write** token — used by `get-usage.sh`, kept in `.env` (git-ignored),
- a **read-only** token — embedded in the widget (so a leak can't overwrite data).
Verify which token is which by testing: a read-only token must fail a `SET` with NOPERM.

`get-usage.sh` stores this JSON under the Redis key `claude:usage` (timestamp in
Asia/Bangkok):
```json
{"session_pct":N,"week_pct":N,"fable_pct":N|null,"fable_status":"ok|rate_limited","updated":"ISO8601+07:00"}
```
Push with:
```bash
curl -s -X POST "$UPSTASH_REDIS_REST_URL/set/claude:usage" \
     -H "Authorization: Bearer $UPSTASH_WRITE_TOKEN" --data-raw "$JSON"
```
Read back with the read-only token to confirm: `GET $URL/get/claude:usage` returns
`{"result":"<the json string>"}`.

Put in `.env` (chmod 600, git-ignored): `UPSTASH_REDIS_REST_URL`, `UPSTASH_WRITE_TOKEN`
(and `API_KEY` only if you also build the optional path in part 5).

## 3. Cron — respect the rate limit
`/usage` reads a server-side endpoint cached ~5 min; polling too often rate-limits the
per-model breakdown and HIDES the Fable bar. Measured: 1 min throttles; 2 min survives ~5
calls then throttles; 3 min couldn't even be validated (still throttled after 15 min
quiet); recovery from a throttle takes roughly an hour. The iOS widget only refreshes
every ~15–30 min anyway. So schedule at **every 5 minutes**, never tighter:
```cron
*/5 * * * * bash -c /abs/path/claude-usage/get-usage.sh
```

## 4. Scriptable widget (claude-usage-widget.js)
A single `.js` file for the Scriptable iOS app. Config block at top:
`UPSTASH_URL`, `READ_TOKEN` (read-only), `KEY = "claude:usage"`, `BG_COLOR` (hex).
- Fetch `GET {UPSTASH_URL}/get/{KEY}` with `Authorization: Bearer {READ_TOKEN}`, then
  `JSON.parse(resp.result)`. Handle `result == null` and network errors gracefully.
- Detect `config.widgetFamily` and render:
    - `accessoryCircular`   : single-value ring gauge (session%) via DrawContext
    - `accessoryRectangular`: Session / Week / Fable
    - `accessoryInline`     : compact `Claude S..% W..% F..%`
    - Home Small/Medium     : card with Session, Week, Fable rows + `updated HH:MM` footer
- Fable: show `%`, but if `fable_status=="rate_limited"` (or `fable_pct` null) show the
  text `rate limit`.
- Allow per-widget background override via the Scriptable "Parameter" field (`#RRGGBB`).
  Note: Lock Screen widgets can't set a background — iOS controls it.
- Theme = Anthropic (orange/cream): background cream `#F0EEE6`, values Claude clay
  `#CC785C`, deep clay `#BD4B2F` for high usage (>=85%), ink text `#28261B`, warm gray
  `#8A8981` for muted/rate-limit.
Deliver the file (with the real read-only token) so I can paste it into Scriptable, and
keep a placeholder version for git. Tell me to install the free Scriptable app first
(App Store: https://apps.apple.com/app/scriptable/id1405459188), then how to add the
widget to the Home screen and Lock screen.

## 5. Optional backup — self-host API + Cloudflare Tunnel (optional/cloudflare/)
Optional, only if I want an independent fallback that doesn't depend on Upstash. Put these
under `optional/cloudflare/`:
- `server.py` — pure Python stdlib HTTP server; reads the repo-root `usage.txt`; returns
  the same JSON shape; auth via a 32-char key (`X-API-Key` or `Authorization: Bearer`,
  `hmac.compare_digest`); `/health` public, `/usage` authed.
- `docker-compose.yml` — `image: python:3.12-slim` (NO Dockerfile), `command: python
  server.py`, mount `./server.py` and `../../usage.txt` read-only, `env_file: ../../.env`,
  publish `8091:8000`, and attach to the existing external docker network
  `0-tunnel_cloudflared` so the token-based `cloudflared` container can reach it at
  `http://claude-usage-api:8000` (it cannot reach host localhost). Point the tunnel's
  public hostname there.
`get-usage.sh` already writes `usage.txt`, so this path works alongside the Upstash push.

## General
- Keep every secret out of git: `.env` git-ignored; the committed widget and compose use
  placeholders; scripts read secrets from `.env`.
- Use absolute paths in cron/scripts.
- After each part, actually run/curl it and show the result, not just the code.
