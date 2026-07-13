# Build prompt — Claude usage monitor stack

A single prompt to hand to Claude Code to build this project end-to-end.

---

Build a "Claude usage" monitoring stack on this Linux host that exposes my Claude Code
usage as a private JSON API and displays it in an iPhone Scriptable widget. Work in
`./claude-usage`. Implement all parts below and verify each one before moving on.

## 1. Data collector (get-usage.sh)
There is a long-running tmux session (name: `claude-usage.1`) with `claude` open.
Write `get-usage.sh` that:
- sends `/usage` + Enter to the tmux session, waits ~3s for render,
- captures the pane to `output.txt`, then sends Escape,
- parses three limit bars by label and extracts the integer percent of each:
    - `Current session`            -> session
    - `Current week (all models)`  -> week
    - `Current week (Fable)`       -> fable   (fallback: any `Current week (...)` line
                                               that is NOT `(all models)`)
- IMPORTANT: if the Fable line is missing (the per-model section is rate-limited /
  didn't render), write `fable=rate_limited` instead of a number.
- writes `usage.txt` in key=value form (`session=`/`week=`/`fable=`), truncating in place
  so a bind-mounted container sees updates without a restart.

## 2. HTTP API (server.py + docker-compose.yml, NO Dockerfile)
- Pure Python stdlib only (no pip). ThreadingHTTPServer.
- Reads `usage.txt` each request; returns JSON:
    `{"session_pct":N,"week_pct":N,"fable_pct":N|null,"fable_status":"ok|rate_limited|unknown","updated":ISO8601}`
  Parse key=value; when `fable=rate_limited` -> `fable_pct` null + status `rate_limited`.
  Keep a fallback parser for the old `N% used` line format.
- Timestamp `updated` from `usage.txt` mtime in Asia/Bangkok (UTC+7).
- Auth: require a random 32-char API key via header `X-API-Key` OR `Authorization: Bearer`.
  Use `hmac.compare_digest`. Generate the key, store it in `.env` (chmod 600), inject via
  compose env. `GET /usage` requires auth; `GET /health` is public.
- `docker-compose.yml`: run `image: python:3.12-slim` with `command: ["python","server.py"]`,
  mount `./server.py` and `./usage.txt` read-only, publish a host port (e.g. 8091->8000),
  `restart: unless-stopped`.
- Bring it up with `docker compose up -d` and test: /health=200, no key=401, wrong key=401,
  correct key (both header styles)=200.

## 3. Cloudflare tunnel wiring
There is already a running token-based `cloudflared` container on an external docker
network. The tunnel CANNOT reach host localhost, so attach the API container to that
same external network (declare it in compose as `external`) and point the tunnel's public
hostname to `http://<api-container-name>:8000`. Verify the public HTTPS URL returns 200
for /health and authenticated /usage.

## 4. Cron scheduling — respect the rate limit
The `/usage` data comes from an endpoint cached ~5 minutes server-side; polling too often
rate-limits the per-model breakdown and HIDES the Fable bar. Empirically a 1–2 minute
interval gets throttled and recovery takes >8 minutes. So schedule `get-usage.sh` via cron
at every 5 minutes (`*/5`). Do not go tighter — the iOS widget only refreshes every
~15–30 min anyway, so faster polling gives no benefit and risks throttling.

## 5. Scriptable widget (claude-usage-widget.js)
A single `.js` file for the Scriptable iOS app that fetches the API and renders:
- Config block at top: `API_URL`, `API_KEY`, and `BG_COLOR` (hex). Allow per-widget
  override of the background via the Scriptable "Parameter" field (accept `#RRGGBB` or
  `RRGGBB`).
- Detect `config.widgetFamily` and render:
    - `accessoryCircular`   : a single-value ring gauge (session%) drawn with DrawContext
    - `accessoryRectangular`: Session / Week / Fable
    - `accessoryInline`     : compact `Claude S..% W..% F..%`
    - Home Small/Medium     : card with Session, Week, Fable rows + `updated HH:MM` footer
  Note: Lock Screen (accessory) widgets can't set a background — iOS controls it.
- Fable display: show `%`, but if `fable_status=="rate_limited"` (or `fable_pct` null) show
  the text `rate limit`.
- Theme = Anthropic (orange/cream): background cream `#F0EEE6`, values Claude clay
  `#CC785C`, deep clay `#BD4B2F` for high usage (>=85%), ink text `#28261B`, warm gray
  `#8A8981` for muted/rate-limit. Ensure text contrast works on the light background.
- Handle fetch errors gracefully (render an error state, never crash).
Deliver the file so I can paste it into Scriptable.

## General
- Use absolute paths in cron/scripts. Keep the API key out of any git history.
- After each part, actually run/curl it and show the result, not just the code.
