# Phase 1 runbook: chat through AgentGateway

```
curl / chat UI -> localhost:8080 -> (port-forward) -> AgentGateway in kind -> host Ollama (Metal GPU)
```

1. Start OrbStack, then `make up`.
2. Make Ollama reachable from containers (it binds to localhost by default):
   `launchctl setenv OLLAMA_HOST 0.0.0.0:11434`, then quit and reopen the Ollama app. Keep the macOS firewall on.
3. `make ollama-check` — must print `ok`.
4. `make platform` — installs Gateway API, AgentGateway, the Gateway, the Ollama backend and the `/llm` route.
5. In a second terminal: `make gateway-forward`.
6. `make smoke` (default model `qwen2.5:7b`; try `./scripts/smoke-chat.sh gemma4:e4b`).

Exit criterion: step 6 returns a completion. Chat UI wiring and Grafana traces are the next Phase 1 increments.

Known unknowns (not verified against a live cluster yet): whether the gateway needs a path rewrite for
OpenAI-style clients that append `/chat/completions` to `/llm`; adjust `llm-route.yaml` if smoke fails.
