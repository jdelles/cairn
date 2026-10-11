# Cairn — the Makefile is the single interface; CI runs the same targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help
CLUSTER ?= cairn

.PHONY: help bootstrap doctor fmt lint test build ci up down clean

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

down: ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER)

clean: ## Remove build artifacts
	cargo clean
	rm -rf agents/.venv agents/.pytest_cache agents/.ruff_cache
