#!/usr/bin/env bash
# Checks local prerequisites. Exits non-zero if a required tool is missing.
set -u
fail=0
need() { if command -v "$1" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; else printf "  MISSING %s  (%s)\n" "$1" "$2"; fail=1; fi; }
opt()  { if command -v "$1" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; else printf "  (optional) %s not found  (%s)\n" "$1" "$2"; fi; }
echo "Required:"
need cargo "rustup"; need uv "brew install uv"; need docker "OrbStack"; need kind "brew install kind"
need kubectl "brew install kubectl"; need helm "brew install helm"; need make "xcode-select --install"
echo "Optional:"
opt flux "brew install fluxcd/tap/flux"; opt pre-commit "brew install pre-commit"; opt gitleaks "brew install gitleaks"; opt ollama "brew install ollama"
if command -v ollama >/dev/null 2>&1; then
  if curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then echo "  ok   ollama is running"; else echo "  WARN ollama installed but not running (host LLM needs it)"; fi
fi
if [ "$(uname -s)" = "Darwin" ]; then echo "RAM: $(( $(sysctl -n hw.memsize) / 1073741824 )) GB (24 GB: cap OrbStack at ~10 GB)"; fi
exit $fail
