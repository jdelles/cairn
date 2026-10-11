# Phase 2: first MCP tool (finance-mcp)

`crates/finance-mcp` is a Rust MCP server (rmcp 3.5.1, streamable HTTP at `/mcp`). Numbers come from SQL integer sums
and `finance-core`; the LLM only chooses tools and explains results. Tools so far:

- `list_accounts` — accounts with transaction counts and net cash flow (cents)
- `spending_by_category(start, end)` — exact category totals for a date range; uncategorized spend is explicit

Verified in CI-equivalent conditions: unit tests, clippy, and an end-to-end run against a real Postgres 16
(migrations, synthetic seed, initialize/tools/list/tools/call over HTTP, error results flagged `isError: true`).
Verified on a live cluster: the image builds, the pod runs as UID 65532, and AgentGateway accepts the MCP backend.
Still to verify: a real MCP call *through the gateway* (`make smoke-mcp`).

## Run it (after `make platform` and `make data`)
1. `make db-seed` — applies `db/migrations/*.sql` (tracked in `schema_migrations`) and loads **synthetic** demo data.
2. `make mcp` — builds the image, loads it into kind, deploys finance-mcp, routes `/mcp` through the gateway.
3. `make gateway-forward`, then use any MCP client (e.g. `npx @modelcontextprotocol/inspector`, transport
   Streamable HTTP, URL `http://localhost:8080/mcp`).

## Lessons learned (2026-10-11)
- `runAsNonRoot` needs a numeric user: the image and pod use UID 65532, not the name `nonroot`.
- rmcp enables DNS-rebinding protection by default (only `localhost`/`127.0.0.1`/`::1` Host headers). Behind the gateway the
  Host is the in-cluster Service name, which returned `403 Forbidden: Host header is not allowed`. finance-mcp now takes an
  `ALLOWED_HOSTS` allowlist (defaults include `finance-mcp.cairn.svc.cluster.local`); the protection stays on. Verified
  locally with spoofed Host headers (200 for allowed names, 403 for others).
- A repo-wide `.gitignore` rule `data/` silently excluded `infra/platform/data/`; guardrail rules are now anchored (`/data/`).
- cargo-deny needed `CDLA-Permissive-2.0` (Mozilla CA bundle via sqlx/rustls) added to the license allowlist.
- AgentGateway accepted `protocol: StreamableHTTP` for the MCP target.

## Known unknowns / follow-ups
- Database TLS is `sslmode=require` (encrypted, server cert not verified). `verify-ca` with the `cairn-db-ca` secret is part of
  the Phase 3 security gate.
- Only synthetic data may be loaded until that gate passes.
