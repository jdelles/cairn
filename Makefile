# Cairn — the Makefile is the single interface; CI runs the same targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help
CLUSTER ?= cairn

.PHONY: help bootstrap doctor fmt lint test build ci up down clean platform ollama-check gateway-forward smoke ui ui-forward

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
export GWAPI_VERSION AGW_VERSION

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
	kubectl -n agentgateway-system port-forward svc/agentgateway-proxy 8080:80

smoke: ## Send one chat through the gateway (needs `make gateway-forward` running)
	./scripts/smoke-chat.sh

ui: ## Deploy the chat UI (Open WebUI) wired to the gateway
	kubectl apply -f infra/platform/ui/open-webui.yaml
	@kubectl -n cairn get secret open-webui-secret >/dev/null 2>&1 || \
	  kubectl -n cairn create secret generic open-webui-secret --from-literal=key=$$(openssl rand -hex 32)
	kubectl -n cairn rollout status deploy/open-webui --timeout=300s
	@echo "Next: make ui-forward, then open http://localhost:3000"

ui-forward: ## Expose the chat UI on http://localhost:3000 (leave running)
	kubectl -n cairn port-forward svc/open-webui 3000:80

down: ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER)

clean: ## Remove build artifacts
	cargo clean
	rm -rf agents/.venv agents/.pytest_cache agents/.ruff_cache
