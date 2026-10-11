# Phase 1 runbook: chat through AgentGateway

```
curl / chat UI -> localhost:8080 -> (port-forward) -> AgentGateway in kind -> host Ollama (Metal GPU)
```

1. Start OrbStack, then `make up`.
2. Make Ollama reachable from containers (it binds to localhost by default):
   `launchctl setenv OLLAMA_HOST 0.0.0.0:11434`, then quit and reopen the Ollama app. Keep the macOS firewall on.
   This is a Phase 1a shortcut: Phase 1b restricts Ollama to the OrbStack bridge address (see the security gate in `docs/PLAN.md`).
3. `make ollama-check` — must print `ok`.
4. `make platform` — installs Gateway API, AgentGateway, the Gateway, the Ollama backend and the `/llm` route.
5. In a second terminal: `make gateway-forward`.
6. `make smoke` (default model `qwen2.5:7b`; try `./scripts/smoke-chat.sh gemma4:e4b`).

Exit criterion: step 6 returns a completion. Chat UI wiring and Grafana traces are the next Phase 1 increments.

Verified on a live cluster (2026-10-11): `make smoke` returns a completion, and Open WebUI chats through `/llm`.

## Chat UI (Open WebUI)

1. `make ui` — deploys Open WebUI v0.12.0 in namespace `cairn`, pointed at the gateway (`/llm`), with a generated
   secret key that stays only in your cluster.
2. `make ui-forward`, then open http://localhost:3000. The first account you create becomes the admin. After that,
   set `ENABLE_SIGNUP` to `"false"` in `infra/platform/ui/open-webui.yaml` and `make ui` again.
3. Pick a model. If the model list is empty (the gateway may not serve `GET /llm/models`), open
   Admin Settings -> Connections -> the OpenAI connection and add `qwen2.5:7b` and `gemma4:e4b` under model IDs.

Verified: chat works through the gateway. If the model list is empty, add model IDs by hand as above.
Open WebUI's built-in RAG downloads a small embedding model on first use; we are not using that feature.
`kubectl port-forward` can drop on long connections; the `*-forward` targets reconnect automatically.

## Data stores (Postgres + Qdrant)

`make data` installs the CloudNativePG operator (chart 0.29.0) and a one-instance `cairn-db` cluster, plus Qdrant
(chart 1.19.1) with a generated API key, all in namespace `cairn`. `make data-status` lists pods/services/secret names.

In-cluster endpoints (for later services): Postgres `cairn-db-rw.cairn.svc:5432` (credentials in secret
`cairn-db-app`), Qdrant `qdrant.cairn.svc:6333` REST / `:6334` gRPC (key in the chart-generated secret).

Verified: `cairn-db` reports healthy, Qdrant runs with a generated API key (secret `qdrant-apikey`).
Secrets stay in the cluster; never paste them into the repo or chats. No NetworkPolicies yet (Phase 1b gate).
