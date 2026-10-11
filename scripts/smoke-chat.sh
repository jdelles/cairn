#!/usr/bin/env bash
# End-to-end smoke test: client -> AgentGateway (localhost:8080) -> host Ollama.
set -euo pipefail
MODEL="${1:-qwen2.5:7b}"
curl -fsS localhost:8080/llm -H 'content-type: application/json' -d "{
  \"model\": \"$MODEL\",
  \"messages\": [{\"role\": \"user\", \"content\": \"Reply with exactly: gateway ok\"}]
}" | python3 -m json.tool
