# Phase 2: first MCP tool (finance-mcp)

`crates/finance-mcp` is a Rust MCP server (rmcp 3.5.1, streamable HTTP at `/mcp`). Numbers come from SQL integer sums
and `finance-core`; the LLM only chooses tools and explains results. Tools so far:

- `list_accounts` — accounts with transaction counts and net cash flow (cents)
- `spending_by_category(start, end)` — exact category totals for a date range; uncategorized spend is explicit

Verified in CI-equivalent conditions: unit tests, clippy, and an end-to-end run against a real Postgres 16
(migrations, synthetic seed, initialize/tools/list/tools/call over HTTP, error results flagged `isError: true`).
NOT yet verified: the container image build, the in-cluster deployment, and the gateway MCP route.

## Run it (after `make platform` and `make data`)
1. `make db-seed` — applies `db/migrations/*.sql` (tracked in `schema_migrations`) and loads **synthetic** demo data.
2. `make mcp` — builds the image, loads it into kind, deploys finance-mcp, routes `/mcp` through the gateway.
3. `make gateway-forward`, then use any MCP client (e.g. `npx @modelcontextprotocol/inspector`, transport
   Streamable HTTP, URL `http://localhost:8080/mcp`).

## Known unknowns
- `finance-mcp-route.yaml` uses `protocol: StreamableHTTP`; AgentGateway docs only show `SSE`. If `kubectl apply`
  rejects it, check the allowed values (`kubectl explain agentgatewaybackend.spec.mcp.targets.static.protocol`).
- Database TLS is `sslmode=require` (encrypted, server cert not verified). Moving to `verify-ca` with the
  `cairn-db-ca` secret is part of the Phase 3 security gate.
- Only synthetic data may be loaded until that gate passes.
