# Cairn — Setup & Implementation Plan

*Drafted 2026-10-11. Goal: a family-CFO AI platform on a production-style stack that runs on one Mac.*

## 1. Target architecture

```
Chat UI (Rust: Axum + Leptos)
        │  OpenAI-compatible / MCP / A2A over HTTP+SSE
        ▼
AgentGateway  ◄── single front door: authn, routing, rate limits, guardrails, OTel traces
  ├── LLM routes ──► KServe InferenceServices (in-cluster)  +  Ollama on host (Metal GPU)
  ├── MCP routes ──► finance-mcp (Rust)   market-mcp (Rust)   planner-mcp (Rust)   docs-mcp
  ├── A2A routes ──► cfo-agent (orchestrator) · ingest-agent · analyst-agent · portfolio-agent
  └── (agents call tools/models only back through the gateway)
Data plane:  Postgres (CloudNativePG) · Qdrant (vectors) · S3-compatible store (raw statements) · NATS/Knative Eventing
Platform:    kind (on OrbStack/Docker) · Gateway API · Knative Serving/Eventing · KServe · Flux (GitOps)
Observability: OpenTelemetry → Prometheus / Grafana / Loki / Tempo
```

Design rules:
1. **Everything goes through AgentGateway** (UI → gateway → anything). Agents never talk to MCP servers or models directly. This gives one place for auth, audit logging and policy — important with financial data.
2. **LLMs never do arithmetic.** Net worth, budgets, cash-flow projections, tax and mortgage/RSU scenarios are deterministic Rust tools exposed over MCP; the LLM chooses tools and explains results.
3. **Postgres is the source of truth** for transactions, accounts, holdings. The vector DB holds only derived/semantic material (statement text, merchant notes, advice history).
4. **Financial data stays local.** Local models only for anything touching statements. No real data in git, ever (see §6).

## 2. Technology choices (with the judgment calls)

| Layer | Choice | Notes |
|---|---|---|
| Cluster | kind on OrbStack | Multi-node kind config in repo. OrbStack is the lighter Docker runtime on Apple Silicon. |
| Gateway | AgentGateway (Rust, Linux Foundation) | Handles LLM, MCP and A2A traffic natively. Runs in-cluster; Gateway API for ingress. |
| Model serving | KServe (raw-deployment mode first) + Knative Serving later | Raw mode avoids the heaviest dependency stack up front; Knative adds scale-to-zero for MCP servers/agents in Phase 4. |
| Models | LLM via Ollama on host; **Quyet** (open-source decision model, Apache-2.0) for the JEV-style slot; a small embedding model | Apple GPU (Metal) is **not** reachable from inside kind containers — see below. |
| Vector DB | Qdrant (Rust) | Fits the Rust-first rule; pgvector is the fallback if you want one fewer system. |
| Relational | Postgres via CloudNativePG operator | Real operator-managed DB, backups, migrations with `sqlx`. |
| Object store | MinIO (or Garage, Rust) | Raw statement PDFs/CSVs, encrypted at rest. |
| Eventing | Knative Eventing + NATS (or Kafka-lite) | Statement uploaded → parse → categorize → notify, as events. |
| MCP servers | Rust, official `rmcp` SDK | |
| Agents | Python (LangGraph) with A2A SDK | Rust agent frameworks are immature; Python is the sanctioned "secondary". Reuses patterns from your remediation agent. |
| UI | Rust: Axum + Leptos | See note below. |
| GitOps / IaC | Flux + Kustomize/Helm; OpenTofu for cluster bootstrap and future cloud | Infra lives beside code; `make up` rebuilds the whole lab from scratch. |
| Secrets | **Never in the repo** (public repo): macOS Keychain / gitignored `local/` overlay, injected into the cluster by `make up`. | Encrypted secrets can live in git safely. |
| CI | GitHub Actions + Makefile (same targets locally and in CI) | |

**Model serving on Apple Silicon (important constraint):** containers inside kind get CPU only. Practical split:
- **In-cluster (KServe)**: CPU-friendly models — an embedding model and **Quyet Small (330M) or Tiny (180M)**, the open-source JEV-style decision models (they run on CPU, ~ms latency). Quyet-Medium (4.7B) needs a 16 GB GPU, so it's out on this 24 GB Mac alongside an LLM; Large (31B) is out. Proves the production pattern.
- **On the host (Ollama, Metal GPU)**: the "real" LLM you will actually chat with, registered in AgentGateway as an external backend. Same gateway route either way, so swapping later (cloud GPU node, etc.) is a config change.

**UI note:** a Rust UI is a real build (~1–2 weeks to a good chat experience). Recommendation: Phase 1 uses an off-the-shelf OpenAI-compatible chat UI pointed at AgentGateway so you have something usable on day one; Phase 3 replaces it with the Leptos UI, adding the net-worth dashboard and statement upload.

## 3. Monorepo layout

```
cairn/
├── Makefile                  # the only interface: make up / test / lint / build / e2e / down
├── .github/workflows/        # ci.yml, images.yml, e2e.yml
├── Cargo.toml                # Rust workspace
├── crates/
│   ├── finance-core/         # money types, categorization rules, net-worth math, scenario calcs
│   ├── finance-mcp/          # MCP server over finance-core + Postgres
│   ├── market-mcp/           # quotes/holdings feed + MCP tools
│   ├── ingest/               # statement parsers (CSV/OFX/PDF text), event consumers
│   ├── planner-mcp/          # what-if tools: RSU/ESPP, mortgage, savings, college, tax
│   └── ui/                   # Leptos app + Axum BFF
├── agents/                   # Python (uv workspace): cfo, ingest, analyst, portfolio + evals
├── models/                   # InferenceService manifests, model cards, download scripts
├── infra/
│   ├── kind/                 # cluster config
│   ├── tofu/                 # bootstrap (cluster, flux)
│   └── clusters/local/       # Flux: infrastructure/ (operators) and apps/ (our services)
├── db/migrations/            # sqlx migrations
├── docs/                     # ADRs, runbooks, threat model
└── fixtures/                 # synthetic statements only
```

## 4. Phased implementation

**Phase 0 — Foundations (day 1–2)**
- Verify Mac prerequisites: RAM (32 GB+ recommended; 16 GB is workable only if Knative/Istio are skipped), OrbStack, `kind`, `kubectl`, `helm`, `flux`, `rustup`, `uv`, `ollama`, `just`/`make`, `sops`, `age`, `gh`.
- Create the GitHub repo, monorepo skeleton, Makefile, pre-commit (fmt, clippy, ruff, gitleaks), ADR-001 recording the choices above.
- Exit: `make lint test` green locally and in GitHub Actions on an empty skeleton.

**Phase 1 — Platform walking skeleton (week 1)**
- `make up`: kind cluster → Flux → Gateway API → AgentGateway → Postgres → Qdrant → object store → observability.
- Ollama on host with one chat LLM + one embedding model; AgentGateway routes `/v1/chat/completions` to it.
- Off-the-shelf chat UI → AgentGateway → LLM. 
- **Phase 1a (done in PR #5):** gateway → host Ollama smoke path over plain HTTP. This is a deliberate, temporary shortcut.
- **Phase 1b — transport security, step 1:** bind Ollama to the OrbStack bridge address only (not `0.0.0.0`) and keep the macOS firewall on; cert-manager with a local CA; HTTPS listener on the gateway.
- Exit: you chat with a local model through the gateway; traces visible in Grafana.

**Phase 2 — KServe + first MCP tool (week 2)**
- Install KServe; deploy an embedding model and the JEV-style model as InferenceServices; route via gateway.
- `finance-core` + `finance-mcp` with schema (accounts, transactions, holdings, categories) and first tools: `list_accounts`, `search_transactions`, `spending_by_category`.
- First agent (`cfo-agent`, LangGraph) discovering tools through the gateway; A2A endpoint exposed.
- Exit: "How much did we spend on dining last month?" answered from seeded synthetic data with a cited tool call.

**Phase 3 — Statement ingestion (weeks 3–4)**
- **SECURITY GATE — no real statements or balances enter the system until all of these are true:** (1) gateway listener is HTTPS (Phase 1b); (2) Ollama hop is restricted to the OrbStack bridge, not exposed on the LAN; (3) **mTLS between all in-cluster services** (service mesh, e.g. Istio ambient — confirm AgentGateway compatibility first — or equivalent) and TLS from the gateway to every backend; (4) default-deny NetworkPolicies; (5) Postgres/object-store volumes encrypted. Until then, use `fixtures/` synthetic data only.
- Upload → object store → Knative Eventing → parser → normalization → dedupe → categorization (rules first, LLM for the leftovers, with human-review queue).
- Prefer CSV/OFX/QFX exports over PDF wherever the bank offers them (far more reliable); PDF path via text extraction + schema-validated LLM extraction, with reconciliation checks (statement ending balance must tie out).
- Start with Wells Fargo checking + one credit card; add institutions one at a time.
- Leptos UI replaces the stock chat UI; adds upload, review queue, and spending views.
- Exit: real statements ingested end-to-end with balances reconciling to the penny.

**Phase 4 — Net worth & market data (weeks 4–6)**
- `market-mcp`: streaming quotes → cached prices → net-worth service (SSE to the UI).
- Holdings: manual/CSV import first (E*Trade RSU/ESPP and brokerage positions), then direct API/aggregator integration once the model is stable.
- Knative Serving scale-to-zero for MCP servers and agents.
- Exit: live net-worth tile that updates during market hours.

**Phase 5 — CFO behaviors (ongoing)**
- `planner-mcp` scenario tools; `portfolio-agent` (concentration, tax-lot awareness, rebalancing flags); `analyst-agent` (subscriptions, anomalies, cash-flow forecast).
- Proactive "CFO briefing" (weekly job): what changed, what to act on, hard truths.
- Eval harness: golden questions with expected tool calls and numerically verified answers; runs in CI against synthetic data.

**Phase 6 — Hardening**
- Re-verify the Phase 3 security gate (mTLS, NetworkPolicies, TLS everywhere) with a scripted check in `make e2e`.
- AuthN (OIDC passkeys via Keycloak/Authentik behind the gateway), per-tool authorization policies, audit log, encrypted backups (CNPG → object store), restore drill, threat model.

## 5. CI/CD & Makefile contract

Makefile targets (identical locally and in CI): `make bootstrap`, `up`, `down`, `lint`, `test`, `build`, `images`, `e2e`, `fmt`, `sbom`.

GitHub Actions:
- **ci.yml** (every PR): `cargo fmt/clippy/test` with sccache, `ruff` + `pytest` via uv, `kustomize build | kubeconform`, `gitleaks`, `trivy` config scan, `cargo deny`.
- **images.yml** (main): multi-arch (arm64+amd64) buildx → GHCR, cosign-signed, SBOM attached.
- **e2e.yml** (nightly + label): spin up kind in the runner, install the platform, run the golden-question evals against synthetic data.
- Flux image-automation or tag bumps promote versions via PR — GitOps all the way.

## 6. Security & privacy (non-negotiable for this use case)
- **Transport security is gated, not deferred:** plain HTTP is allowed only while the system holds synthetic data. The Phase 3 security gate (HTTPS at the gateway, restricted Ollama hop, mTLS in-cluster, NetworkPolicies) must pass before any real statement is ingested. Known limitation: Ollama itself has no TLS/auth, so that hop is protected by network restriction, not cryptography.
- Raw statements and real balances never enter git, CI, or logs. CI uses `fixtures/` synthetic data only.
- Secrets and personal config live only in `local/` / Keychain — not even encrypted in git (public repo). Object store and Postgres volumes encrypted (FileVault + app-level encryption for statement blobs).
- Redaction in traces/logs (account numbers masked at the gateway).
- Models are local; no financial content sent to hosted LLM APIs unless you explicitly opt in per route.
- Advice disclaimer baked into the CFO agent prompt; it's decision support, not a licensed advisor.

## 7. Decisions (resolved 2026-10-11)
1. **JEV-style model:** Quyet (github.com/ncchinh/quyet, Apache-2.0, `pip install quyet`, HTTP `/v1/systemone`). It reads a state (text/JSON) and returns a typed choice/score/yes-no with calibrated probability in one forward pass, no text generation. Use for: transaction categorization, "is this charge anomalous/recurring?", alert triage, and decision gating for the CFO agent. TypeSafe's own Jev 1.13 is a closed hosted API, so it's excluded from the default local-only path (could be a de-identified, opt-in route later). Fine-tuning Quyet on your own corrected categories is a Phase 5 option.
2. **Hardware:** M4, 24 GB. Staged install: Phase 1 = kind (1 control plane + 2 workers, ~8 GB cap in OrbStack) + AgentGateway + data stores; KServe raw mode in Phase 2; Knative in Phase 4. LLM on host via Ollama with a ~7–14B 4-bit model; keep OrbStack memory limit ≤ 10 GB so the model has room.
3. **Market data:** free tiers only (Alpaca IEX websocket, Finnhub, Twelve Data fallback); holdings via manual/CSV import.
4. **UI:** stock OpenAI-compatible chat UI in Phase 1; custom Leptos UI in Phase 3.
5. **Repo:** public `jdelles/cairn` (Apache-2.0), name chosen 2026-10-11. Guardrails: no real data or secrets in git, gitleaks + push protection, synthetic fixtures only.

## 8. First actions once approved
1. Phase 0 skeleton in `jdelles/cairn` (done: see repo).
2. Write ADR-001 and the kind + Flux bootstrap.
3. Get "hello gateway" — Ollama behind AgentGateway answering from the chat UI — running locally.
