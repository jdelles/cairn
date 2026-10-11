# Cairn

An open-source **family CFO** platform: ingest bank and credit-card statements, keep a live picture of net worth,
and get decision support from agents that use deterministic finance tools over MCP.

> Status: early (Phases 0–2 in progress). Chat works end to end through the gateway; the first finance MCP tool is
> deployed. See [`docs/PLAN.md`](docs/PLAN.md) for the roadmap and [Status](#status) below.

## Architecture

```
Chat UI ──► AgentGateway ──► agents (A2A) · MCP tools · models (LLM + decision model) · Postgres · Qdrant
```

- **Rust first** (finance math, MCP servers, ingestion, UI), **Python second** (LangGraph agents)
- kind · AgentGateway · KServe · Knative · Flux — infrastructure lives in this repo
- The LLM never does arithmetic; numbers come from tested Rust tools

## Status

| Piece | State |
|---|---|
| Monorepo, CI (lint/test, cargo-deny, gitleaks), Makefile | done |
| kind cluster (`make up`) | done, verified |
| AgentGateway + route to host Ollama (`make platform`) | done, verified |
| Chat UI: Open WebUI through the gateway (`make ui`) | done, verified |
| Postgres (CloudNativePG) + Qdrant (`make data`) | done, verified |
| `finance-mcp` (Rust MCP server, 2 tools) deployed (`make mcp`) | pod + gateway backend accepted; end-to-end call through the gateway **pending** (Host-header fix in review) |
| Transport security (HTTPS, mTLS, NetworkPolicies) | planned: **gate before any real data** |
| KServe + Quyet decision model, ingestion, net worth, CFO agents | not started |

## Quick start (macOS, Apple Silicon, OrbStack)

```sh
make doctor           # check prerequisites; start OrbStack and Ollama if it complains
make bootstrap        # python deps + git hooks
make ci               # lint + tests
make up               # kind cluster (3 nodes)

# Ollama must listen beyond localhost so the cluster can reach it (see docs/PHASE-1.md)
make ollama-check
make platform         # Gateway API + AgentGateway + /llm route to host Ollama
make ui               # chat UI; then `make ui-forward` -> http://localhost:3000
make data             # Postgres + Qdrant
make db-seed          # migrations + SYNTHETIC demo data
make mcp              # build/deploy finance-mcp, route /mcp via the gateway

make gateway-forward  # leave running; then in another terminal:
make smoke            # chat through the gateway
make smoke-mcp        # MCP initialize / tools/list / tools/call through the gateway
```

Re-running any target is safe. `make down` deletes the cluster; `make down && make up && make platform` is a clean slate.
The chat LLM runs on the host (Ollama, Apple GPU) because containers on macOS cannot use Metal; see the plan.

## Docs

- [`docs/PLAN.md`](docs/PLAN.md) — architecture, phases, security gate
- [`docs/PHASE-1.md`](docs/PHASE-1.md) — gateway, chat UI, data stores runbook
- [`docs/PHASE-2.md`](docs/PHASE-2.md) — finance MCP server
- [`docs/adr/`](docs/adr) — architecture decisions

## Privacy

This repository is public and contains **no real financial data or secrets**. Fixtures are synthetic; personal
configuration lives in a gitignored `local/` directory (see `local-example/`).

## License

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
