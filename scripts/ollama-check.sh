#!/usr/bin/env bash
# Verifies the host Ollama is reachable FROM INSIDE the cluster (the path the gateway uses).
set -euo pipefail
CLUSTER="${CLUSTER:-cairn}"
NODE="${CLUSTER}-control-plane"
ip=$(docker exec "$NODE" getent ahostsv4 host.docker.internal | awk 'NR==1{print $1}')
if docker exec "$NODE" curl -fsS --max-time 5 "http://$ip:11434/api/tags" >/dev/null; then
  echo "ok: Ollama reachable from the cluster at $ip:11434"
else
  cat >&2 <<MSG
FAIL: Ollama is not reachable from the cluster at $ip:11434.
By default Ollama listens on localhost only. Make it listen on all interfaces, then restart it:
  launchctl setenv OLLAMA_HOST 0.0.0.0:11434   # then quit and reopen the Ollama app
  # or in a terminal:  OLLAMA_HOST=0.0.0.0:11434 ollama serve
Note: this exposes Ollama to your local network; keep the macOS firewall on.
MSG
  exit 1
fi
