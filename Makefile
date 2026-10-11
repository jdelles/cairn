# Cairn — the Makefile is the single interface; CI runs the same targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help
CLUSTER ?= cairn

.PHONY: help bootstrap doctor fmt lint test build ci up down clean platform ollama-check gateway-forward smoke ui ui-forward data data-status db-migrate db-seed image-finance-mcp mcp mcp-status smoke-mcp

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

bootstrap: ## Install dev tooling hooks (pre-commit) and sync Python deps
	cd agents && uv sync
	@command -v pre-commit >/dev/null && pre-commit install || echo "tip: install pre-commit (brew install pre-commit)"

doctor: ## Check local prerequisites (Mac: OrbStack, kind, Ollama, ...)
	@./scripts/doctor.sh

fmt: ## Format Rust and Python
	cargo fmt --all
	cd agents && uv run ruff format .

lint: ## Lint (fmt check, clippy, ruff)
	cargo fmt --all -- --check
	cargo clippy --workspace --all-targets -- -D warnings
	cd agents && uv run ruff check . && uv run ruff format --check .

test: ## Run all tests
	cargo test --workspace
	cd agents && uv run pytest

build: ## Build Rust workspace (release)
	cargo build --workspace --release

ci: lint test ## What CI runs on every PR

up: ## Create the local kind cluster (platform install arrives in Phase 1)
	kind create cluster --config infra/kind/kind-config.yaml || true
	kubectl cluster-info --context kind-$(CLUSTER)

include infra/platform/versions.env
export GWAPI_VERSION AGW_VERSION CNPG_CHART_VERSION QDRANT_CHART_VERSION

platform: ## Install Gateway API + AgentGateway and route /llm to host Ollama
	kubectl apply --server-side --force-conflicts -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v$(GWAPI_VERSION)/standard-install.yaml
	helm upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
	  --create-namespace --namespace agentgateway-system --version $(AGW_VERSION)
	helm upgrade -i agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
	  --namespace agentgateway-system --version $(AGW_VERSION) --wait
	kubectl apply -f infra/platform/gateway/gateway.yaml
	./scripts/render-ollama.sh | kubectl apply -f -
	kubectl apply -f infra/platform/gateway/llm-route.yaml
	kubectl -n agentgateway-system wait --for=condition=Programmed gateway/agentgateway-proxy --timeout=180s

ollama-check: ## Verify host Ollama is reachable from inside the cluster
	./scripts/ollama-check.sh

gateway-forward: ## Expose the gateway on localhost:8080 (leave running)
	@echo "forwarding localhost:8080 -> gateway (auto-reconnects; Ctrl-C to stop)"
	@while true; do kubectl -n agentgateway-system port-forward svc/agentgateway-proxy 8080:80; echo "port-forward dropped, reconnecting..."; sleep 1; done

smoke: ## Send one chat through the gateway (needs `make gateway-forward` running)
	./scripts/smoke-chat.sh

ui: ## Deploy the chat UI (Open WebUI) wired to the gateway
	kubectl apply -f infra/platform/ui/open-webui.yaml
	@kubectl -n cairn get secret open-webui-secret >/dev/null 2>&1 || \
	  kubectl -n cairn create secret generic open-webui-secret --from-literal=key=$$(openssl rand -hex 32)
	kubectl -n cairn rollout status deploy/open-webui --timeout=300s
	@echo "Next: make ui-forward, then open http://localhost:3000"

ui-forward: ## Expose the chat UI on http://localhost:3000 (leave running)
	@echo "forwarding http://localhost:3000 -> chat UI (auto-reconnects; Ctrl-C to stop)"
	@while true; do kubectl -n cairn port-forward svc/open-webui 3000:80; echo "port-forward dropped, reconnecting..."; sleep 1; done

data: ## Install Postgres (CloudNativePG) and Qdrant in namespace cairn
	helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
	helm repo add qdrant https://qdrant.github.io/qdrant-helm --force-update
	helm upgrade -i cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace \
	  --version $(CNPG_CHART_VERSION) --wait
	kubectl create namespace cairn --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f infra/platform/data/postgres-cluster.yaml
	helm upgrade -i qdrant qdrant/qdrant --namespace cairn --version $(QDRANT_CHART_VERSION) \
	  -f infra/platform/data/qdrant-values.yaml --wait --timeout 5m
	kubectl -n cairn wait --for=condition=Ready cluster/cairn-db --timeout=300s
	@$(MAKE) --no-print-directory data-status

data-status: ## Show data-store pods, services and secret names (never prints secret values)
	kubectl -n cairn get cluster,pods,svc,pvc
	@echo "secrets:" && kubectl -n cairn get secret -o name | grep -E 'cairn-db|qdrant' || true

db-migrate: ## Apply SQL migrations to the cluster database
	./scripts/migrate.sh

db-seed: ## Migrate and load SYNTHETIC demo data (never real data)
	./scripts/migrate.sh --seed

image-finance-mcp: ## Build the finance-mcp image and load it into kind
	docker build -f Dockerfile.rust --build-arg BIN=finance-mcp -t cairn/finance-mcp:dev .
	kind load docker-image cairn/finance-mcp:dev --name $(CLUSTER)

mcp: image-finance-mcp ## Deploy finance-mcp and route /mcp through the gateway
	kubectl apply -f infra/platform/mcp/finance-mcp.yaml
	kubectl -n cairn rollout restart deploy/finance-mcp
	kubectl -n cairn rollout status deploy/finance-mcp --timeout=180s
	kubectl apply -f infra/platform/mcp/finance-mcp-route.yaml

smoke-mcp: ## MCP initialize/list/call through the gateway (needs `make gateway-forward`)
	./scripts/smoke-mcp.sh

mcp-status: ## Show finance-mcp pod/route status
	kubectl -n cairn get deploy,pods -l app=finance-mcp
	kubectl -n agentgateway-system get agentgatewaybackend,httproute

down: ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER)

clean: ## Remove build artifacts
	cargo clean
	rm -rf agents/.venv agents/.pytest_cache agents/.ruff_cache
