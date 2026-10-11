#!/usr/bin/env bash
# End-to-end MCP smoke test through AgentGateway (needs `make gateway-forward` running):
# initialize -> tools/list -> tools/call spending_by_category (synthetic data: Sep 2026).
set -euo pipefail
URL="${MCP_URL:-http://localhost:8080/mcp}"
H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
hdr=$(mktemp); trap 'rm -f "$hdr"' EXIT

# Print the JSON payload(s) from an SSE or plain JSON response.
show() { python3 -c '
import sys, json
raw = sys.stdin.read()
for line in raw.splitlines():
    line = line.strip()
    if line.startswith("data:") and line[5:].strip().startswith("{"):
        d = json.loads(line[5:]); print(json.dumps(d, indent=2)); break
else:
    print(raw[:2000])
'; }

echo "== initialize"
curl -fsS -D "$hdr" "${H[@]}" "$URL" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cairn-smoke","version":"0"}}}' | show
SID=$(grep -i '^mcp-session-id:' "$hdr" | awk '{print $2}' | tr -d '\r' || true)
SH=(); [ -n "$SID" ] && SH=(-H "mcp-session-id: $SID")
curl -fsS "${H[@]}" "${SH[@]}" "$URL" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null || true

echo "== tools/list"
curl -fsS "${H[@]}" "${SH[@]}" "$URL" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | show

echo "== tools/call spending_by_category (2026-09-01..2026-09-30)"
curl -fsS "${H[@]}" "${SH[@]}" "$URL" -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"spending_by_category","arguments":{"start":"2026-09-01","end":"2026-09-30"}}}' | show
