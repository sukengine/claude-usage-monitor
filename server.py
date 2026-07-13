#!/usr/bin/env python3
"""Minimal usage API: reads usage.txt and serves session/week percentages.

usage.txt format (one entry per line, e.g. produced by get-usage.sh):
    0% used     <- line 1 = current session
    87% used    <- line 2 = current week
"""
import hmac
import json
import os
import re
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USAGE_FILE = os.environ.get("USAGE_FILE", "/data/usage.txt")
API_KEY = os.environ.get("API_KEY", "")
PORT = int(os.environ.get("PORT", "8000"))
TZ = timezone(timedelta(hours=7))  # Asia/Bangkok


def read_usage():
    d = {"session": None, "week": None, "fable": None,
         "fable_status": "unknown", "updated": None}
    try:
        with open(USAGE_FILE) as f:
            content = f.read()
    except FileNotFoundError:
        return d

    kv = {}
    for line in content.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip()

    def as_int(s):
        return int(s) if s.isdigit() else None

    if kv:  # รูปแบบใหม่ key=value
        d["session"] = as_int(kv.get("session", ""))
        d["week"] = as_int(kv.get("week", ""))
        fv = kv.get("fable", "")
        if fv.isdigit():
            d["fable"], d["fable_status"] = int(fv), "ok"
        elif fv == "rate_limited":
            d["fable_status"] = "rate_limited"
    else:  # fallback: รูปแบบเดิม 'N% used' บรรทัดต่อบรรทัด
        nums = [int(m.group(1)) for line in content.splitlines()
                if (m := re.search(r"(\d+)\s*%", line))]
        if len(nums) >= 1:
            d["session"] = nums[0]
        if len(nums) >= 2:
            d["week"] = nums[1]
        if len(nums) >= 3:
            d["fable"], d["fable_status"] = nums[2], "ok"

    d["updated"] = datetime.fromtimestamp(
        os.path.getmtime(USAGE_FILE), TZ).isoformat()
    return d


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quieter logs
        pass

    def _key_ok(self):
        key = self.headers.get("X-API-Key")
        if not key:
            auth = self.headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                key = auth[len("Bearer "):]
        return bool(API_KEY) and key is not None and \
            hmac.compare_digest(key, API_KEY)

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/")

        if path == "/health":
            self._send(200, {"ok": True})
            return

        if not self._key_ok():
            self._send(401, {"error": "unauthorized"})
            return

        if path in ("", "/usage"):
            d = read_usage()
            if d["session"] is None and d["week"] is None:
                self._send(503, {"error": "usage data unavailable"})
                return
            self._send(200, {
                "session_pct": d["session"],
                "week_pct": d["week"],
                "fable_pct": d["fable"],
                "fable_status": d["fable_status"],
                "updated": d["updated"],
            })
            return

        self._send(404, {"error": "not found"})


if __name__ == "__main__":
    if not API_KEY:
        raise SystemExit("API_KEY env var is required")
    print(f"usage-api listening on :{PORT} (file={USAGE_FILE})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
