# AGENTS.md — instructions for AI coding agents working on Cairn

- Cairn is a **public** repo. Never write real financial data, account numbers, statements or secrets into it. Use `fixtures/` (synthetic only) and `local/` (gitignored).
- Rust first, Python second. All numeric/financial math lives in Rust (`crates/finance-core`) using integer cents; the LLM never computes numbers.
- Everything goes through AgentGateway: UI -> AgentGateway -> agents / MCP / models / data. Agents never call tools or models directly.
- `make ci` must pass before committing. Use `make help` for targets.
- Record architecture decisions as ADRs in `docs/adr/`.
