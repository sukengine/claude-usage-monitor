# claude-usage-monitor

Show Claude Code `/usage` (session / weekly / Fable limits) on an iPhone **Scriptable**
widget. Primary path uses **Upstash Redis** (push model) — no public server, no tunnel.

<p align="center">
  <img src="docs/scriptable.jpg" alt="Scriptable widget (Anthropic theme)" width="280">
</p>

## How it works

```
tmux (claude /usage) → get-usage.sh → Upstash Redis (REST) → Scriptable widget (read-only token)
```

The collector only makes an **outbound** HTTPS POST, so nothing needs to be exposed. The
widget reads with a **read-only** token, so even if it leaks it can't overwrite anything.

| Component | File | Role |
|---|---|---|
| Collector | `get-usage.sh` | scrape `/usage` from a tmux `claude` session; push JSON to Upstash |
| Widget | `claude-usage-widget.js` | Scriptable widget (Home + Lock Screen), Anthropic theme |
| Probes | `probe.sh`, `sustain-test.sh` | tooling used to find a safe polling interval |

> An optional self-host path (Docker API + Cloudflare Tunnel) lives in
> [`optional/cloudflare/`](optional/cloudflare/) as a backup — not needed for the primary flow.

## Setup

> **Claude Code users — the easy way:** clone this repo, `cd` into it, open Claude Code and
> paste the prompt from [`BUILD_PROMPT.md`](BUILD_PROMPT.md). It walks through every step
> below (asks you for the Upstash URL/tokens and your tmux session, wires `.env` + cron,
> fills the widget, and verifies each part). The manual steps are below if you prefer.

### Prerequisites
- A tmux session running `claude` so `/usage` can be scraped. If you don't have one:
  ```bash
  tmux new -d -s claude-usage        # then attach and run `claude` inside; target = claude-usage.1
  ```
- A free [Upstash](https://upstash.com) Redis database (login with GitHub/Google).

### Steps
1. **Get Upstash credentials.** In the Upstash console open your Redis DB → REST API:
   copy the **REST URL** and the (write) **REST token**, then create a **read-only** token
   (Tokens → create, read-only). Keep the two tokens separate.
2. **Configure `.env`** (git-ignored):
   ```bash
   cp .env.example .env
   # edit .env: set UPSTASH_REDIS_REST_URL and UPSTASH_WRITE_TOKEN
   chmod 600 .env
   ```
3. **Adjust paths** in `get-usage.sh`: set `DIR` to this repo's absolute path and
   `SESSION_NAME` to your tmux session (e.g. `claude-usage.1`). `chmod +x get-usage.sh`.
4. **Test the collector once** and confirm it pushed:
   ```bash
   ./get-usage.sh                     # expect: "saved: ... | upstash=ok"
   # verify the widget's read path (read-only token):
   curl -s "$UPSTASH_REDIS_REST_URL/get/claude:usage" \
        -H "Authorization: Bearer <READ_ONLY_TOKEN>"
   ```
5. **Schedule it** — every 5 minutes, never faster (see the rate-limit note):
   ```cron
   */5 * * * * bash -c /abs/path/to/claude-usage/get-usage.sh
   ```
6. **Configure the widget** (next section) with your `UPSTASH_URL` + read-only token, then
   paste it into Scriptable.

`get-usage.sh` stores this JSON under the Redis key `claude:usage`:
```json
{"session_pct":5,"week_pct":89,"fable_pct":100,"fable_status":"ok","updated":"...+07:00"}
```
When the Fable bar is rate-limited/absent: `"fable_pct":null,"fable_status":"rate_limited"`.

## Widget

1. **Install Scriptable** (free) on your iPhone/iPad from the App Store:
   https://apps.apple.com/app/scriptable/id1405459188 — then open it once.
2. In Scriptable tap **+** to create a new script and paste the contents of
   `claude-usage-widget.js` (see config below).

Edit the config block in `claude-usage-widget.js`, then paste into Scriptable:
```js
const UPSTASH_URL = "https://YOUR-DB.upstash.io"
const READ_TOKEN  = "YOUR_UPSTASH_READONLY_TOKEN"   // read-only token
const KEY         = "claude:usage"
const BG_COLOR    = "#F0EEE6"   // Home background; or set per-widget via the Parameter field
```
Add it to the Home screen (Small/Medium) or Lock screen (circular / rectangular / inline).
Lock-screen widgets are tinted by iOS — background color applies to Home only.

## ⚠️ Rate limit — poll every 5 minutes, not faster

`/usage` reads a server-side endpoint cached ~5 min. Polling too often rate-limits the
per-model breakdown and **hides the Fable bar**. Measured on this account:

| interval | result |
|---|---|
| 1 min | throttled |
| 2 min | survived 5 calls, throttled on the 6th (~10–12 min) |
| 3 min | couldn't be validated — still throttled after 15 min of quiet |
| 5 min | safe (matches the cache window) |

Recovery from a throttle is slow — **>15 min, roughly an hour**. The iOS widget only
refreshes every ~15–30 min anyway, so faster polling gives no real benefit. **Use `*/5`.**

## Update only while attached (optional)

`get-usage.sh` skips its run when you're **not** attached to your claude container — the
session % doesn't move while you're away, so there's no point scraping (and no point
interrupting the session when you *are* working). It detects the `./cl` docker-attach by a
live `docker attach … -claude-1` process. Disable the gate with `ATTACH_GATE=0` in `.env`,
or change the match with `ATTACH_PATTERN`.
