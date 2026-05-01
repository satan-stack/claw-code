#!/usr/bin/env bash
# jarvis-bridge.sh — mirror what OpenJarvis's ClawCodeAgent invokes.
#
# Useful for sanity-checking the pipeline before driving claw through
# the full `jarvis` CLI. The agent itself constructs an equivalent argv
# in src/openjarvis/agents/claw_code.py.
#
# Usage:
#   scripts/jarvis-bridge.sh "summarize this repository"
#   CLAW_MODEL=haiku scripts/jarvis-bridge.sh "refactor src/auth.rs"
#   CLAW_PERMISSION_MODE=read-only scripts/jarvis-bridge.sh "explain Cargo.toml"

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $(basename "$0") <prompt>" >&2
    exit 64
fi

BINARY="${CLAW_BINARY:-claw}"
MODEL="${CLAW_MODEL:-sonnet}"
PERMISSION_MODE="${CLAW_PERMISSION_MODE:-workspace-write}"
ALLOWED_TOOLS="${CLAW_ALLOWED_TOOLS:-}"
RESUME="${CLAW_RESUME:-}"

if ! command -v "$BINARY" >/dev/null 2>&1 && [[ ! -x "$BINARY" ]]; then
    cat >&2 <<EOF
error: claw binary not found at '$BINARY'.
  Build it:
    cd rust && cargo build --workspace
    export CLAW_BINARY=\$PWD/target/debug/claw
  Or install on PATH:
    cargo install --path crates/rusty-claude-cli --force
EOF
    exit 127
fi

args=(--output-format json --model "$MODEL" --permission-mode "$PERMISSION_MODE")
if [[ -n "$ALLOWED_TOOLS" ]]; then
    args+=(--allowedTools "$ALLOWED_TOOLS")
fi
if [[ -n "$RESUME" ]]; then
    args+=(--resume "$RESUME")
fi
args+=(prompt "$1")

exec "$BINARY" "${args[@]}"
