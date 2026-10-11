# Cairn

An open-source **family CFO** platform: ingest bank and credit-card statements, keep a live picture of net worth,
and get decision support from agents that use deterministic finance tools over MCP.

> Status: early. Phase 0 (skeleton) — see [`docs/PLAN.md`](docs/PLAN.md).

## Architecture

```
Chat UI ──► AgentGateway ──► agents (A2A) · MCP tools · models (LLM + decision model) · Postgres · Qdrant
```

- **Rust first** (finance math, MCP servers, ingestion, UI), **Python second** (LangGraph agents)
- kind · AgentGateway · KServe · Knative · Flux — infrastructure lives in this repo
- The LLM never does arithmetic; numbers come from tested Rust tools

## Quick start

```sh
make doctor     # check prerequisites
make bootstrap  # python deps + git hooks
make ci         # lint + tests
make up         # create the local kind cluster
```

## Privacy

This repository is public and contains **no real financial data or secrets**. Fixtures are synthetic; personal
configuration lives in a gitignored `local/` directory (see `local-example/`).

## License

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
