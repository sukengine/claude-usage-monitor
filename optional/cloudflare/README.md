# Optional: self-host path (Docker + Cloudflare Tunnel)

An **optional backup** to the primary Upstash push model. Instead of pushing to a cloud
KV store, this serves `usage.txt` as a JSON API from your own host and exposes it through
a Cloudflare Tunnel. Use it if you'd rather not depend on Upstash, or want an independent
fallback.

The primary path (root `README.md`) needs none of this.

## Pieces
- `server.py` — stdlib HTTP server; reads the repo-root `usage.txt`, API-key auth
- `docker-compose.yml` — runs it on `python:3.12-slim` (no Dockerfile), publishes `8091`

Depends on the root `get-usage.sh` still writing `usage.txt` (it does, alongside the
Upstash push).

## Run
```bash
# from repo root: make sure .env has API_KEY, and get-usage.sh is producing usage.txt
cd optional/cloudflare
docker compose up -d
```

API:
- `GET /health` — public
- `GET /usage` — needs `X-API-Key: <key>` (or `Authorization: Bearer <key>`)

## Cloudflare Tunnel
A token-based `cloudflared` container (managed elsewhere) cannot reach host `localhost`,
so the compose attaches this container to the external network `0-tunnel_cloudflared` and
the tunnel's public hostname must point to `http://claude-usage-api:8000`.

## Point the widget here instead of Upstash
In `../../claude-usage-widget.js` swap `loadUsage()` back to a direct fetch:
```js
const req = new Request("https://<your-tunnel-host>/usage")
req.headers = { "X-API-Key": "<your key>" }
return await req.loadJSON()
```
