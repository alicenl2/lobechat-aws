#!/bin/bash
# Run ON the EC2 host, ONCE, AFTER you have logged into LobeChat via Casdoor.
# It wires up the per-user rows that can't be seeded before the user exists:
#   - enables the Ollama provider (server-side fetch) + registers qwen2.5:3b
#   - installs the MCPHub MCP tools (aws-documentation, d2) into LobeChat
# Idempotent: safe to re-run.
set -euo pipefail

PG="sudo docker exec -i shared-postgres psql -U postgres -d lobechat"
PGQ="sudo docker exec shared-postgres psql -U postgres -d lobechat -tAc"
MCPHUB_USER=admin
MCPHUB_PASS=admin123

USER_ID=$($PGQ "SELECT id FROM users ORDER BY created_at LIMIT 1;")
if [ -z "$USER_ID" ]; then
  echo "No LobeChat user yet — log into LobeChat via Casdoor first, then re-run."; exit 1
fi
echo "User: $USER_ID"

# ── 1. Ollama provider + model ───────────────────────────────────────────────
$PG <<SQL
UPDATE ai_providers SET enabled=true, fetch_on_client=false
  WHERE id='ollama' AND user_id='${USER_ID}';
INSERT INTO ai_models (id, display_name, provider_id, type, enabled, user_id,
                       abilities, context_window_tokens, source)
VALUES ('qwen2.5:3b','Qwen2.5 3B (local Ollama)','ollama','chat',true,'${USER_ID}',
        '{"functionCall":true}'::jsonb, 32768, 'custom')
ON CONFLICT DO NOTHING;
SQL
echo "Ollama provider + qwen2.5:3b registered."

# ── 2. MCP tools from MCPHub -> LobeChat ─────────────────────────────────────
TOKEN=$(curl -s -m 8 -X POST http://localhost:47008/api/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${MCPHUB_USER}\",\"password\":\"${MCPHUB_PASS}\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s -m 10 -H "x-auth-token: $TOKEN" http://localhost:47008/api/servers -o /tmp/srv.json

USER_ID="$USER_ID" python3 - > /tmp/mcp_insert.sql <<'PY'
import json, os
servers = json.load(open("/tmp/srv.json"))["data"]
user_id = os.environ["USER_ID"]
want = {"aws-documentation": "mcphub-aws-docs", "d2": "mcphub-d2"}
def q(s): return "'" + s.replace("'", "''") + "'"
out = ["DELETE FROM user_installed_plugins WHERE identifier IN ('mcphub-aws-docs','mcphub-d2');"]
for s in servers:
    if s["name"] not in want: continue
    ident = want[s["name"]]
    api = [{"name": t["name"], "description": (t.get("description") or "")[:300],
            "parameters": t.get("inputSchema", {"type": "object", "properties": {}})}
           for t in s.get("tools", [])]
    manifest = {"identifier": ident, "type": "mcp",
                "meta": {"title": ident, "avatar": "\U0001F9F0",
                         "description": ident + " (" + str(len(api)) + " tools)"},
                "api": api}
    custom = {"mcp": {"url": "http://mcphub:3000/mcp/" + s["name"],
                      "auth": {"type": "none"}, "type": "http"}}
    out.append("INSERT INTO user_installed_plugins (user_id, identifier, type, manifest, custom_params) VALUES ("
               + q(user_id) + "," + q(ident) + ",'customPlugin',"
               + q(json.dumps(manifest)) + "::jsonb," + q(json.dumps(custom)) + "::jsonb);")
print("\n".join(out))
PY
$PG < /tmp/mcp_insert.sql
echo "MCP tools installed: mcphub-aws-docs, mcphub-d2"
echo "Done. Hard-refresh LobeChat, pick Ollama -> qwen2.5:3b, enable a plugin."
