# ADR-0001: Architecture and technology choices

Status: accepted (2026-10-11)

## Context
Cairn is a family-CFO platform: ingest statements, track net worth, give decision support through agents.
Requirements: production-style architecture, Rust first / Python second, UI -> AgentGateway -> everything,
kind + AgentGateway + KServe + Knative, open source, infrastructure managed with code, monorepo, real CI with Makefile.

## Decisions
1. **Single front door:** all traffic goes through AgentGateway (LLM, MCP, A2A routes).
2. **Deterministic math in Rust** (`finance-core`, integer cents). LLMs choose tools and explain; they never compute.
3. **Postgres** is the source of truth; **Qdrant** holds derived/semantic data.
4. **Models:** chat LLM on the host via Ollama (Apple GPU/Metal is unreachable from containers on macOS); CPU models
   (embeddings, **Quyet** Small/Tiny decision models) on KServe in-cluster.
5. **Cluster:** kind on OrbStack; GitOps with Flux; staged install for a 24 GB machine.
6. **Public repo, Apache-2.0.** Real data and secrets never enter git; personal config lives in `local/`.
7. **UI:** stock OpenAI-compatible chat UI first, Rust (Axum + Leptos) UI in Phase 3. Buoyant is an optional
   later wall-display/TUI client (it targets embedded/terminal, has no TextField yet).

See `docs/PLAN.md` for phases and exit criteria.
