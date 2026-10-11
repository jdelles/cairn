#!/usr/bin/env bash
# Print the Ollama Service/EndpointSlice/Backend manifest with the Mac's IP filled in.
# The IP is what the kind nodes see as the host (OrbStack: host.docker.internal).
set -euo pipefail
CLUSTER="${CLUSTER:-cairn}"
NODE="${CLUSTER}-control-plane"
ip=""
for name in host.docker.internal host.internal; do
  ip=$(docker exec "$NODE" getent ahostsv4 "$name" 2>/dev/null | awk 'NR==1{print $1}') && [ -n "$ip" ] && break || true
done
[ -n "$ip" ] || { echo "could not resolve the host IP from kind node $NODE" >&2; exit 1; }
echo "host IP seen from cluster: $ip" >&2
sed "s/__OLLAMA_IP__/$ip/" "$(dirname "$0")/../infra/platform/gateway/ollama.yaml.tmpl"
