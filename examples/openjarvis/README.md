# OpenJarvis ↔ Claw Code example

This directory contains a runnable example of using `claw` as the coding
agent inside [OpenJarvis][oj]. The full integration guide lives in
[`docs/integrations/openjarvis.md`](../../docs/integrations/openjarvis.md).

[oj]: https://github.com/satan-stack/openjarvis

## Files

- `jarvis-config.toml` — drop-in `~/.openjarvis/config.toml` that selects
  the `claw_code` agent and points OpenJarvis at the local `claw` binary.
- `jarvis-bridge.sh` — a one-line wrapper that mirrors what OpenJarvis's
  `ClawCodeAgent` invokes; handy for sanity-checking the pipeline
  without going through the full Jarvis CLI.

## Quick start

```bash
# 1. Build claw and put it on PATH (or set CLAW_BINARY).
cd ../../rust && cargo build --workspace --release
export CLAW_BINARY=$PWD/target/release/claw

# 2. Pick a credential path. Anthropic direct is fastest:
export ANTHROPIC_API_KEY=sk-ant-...
# ...or keep everything local with Ollama:
#   ollama serve &
#   ollama pull qwen2.5-coder:1.5b      # best CPU pick (~10s warm turns)
#   export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
#   export OPENAI_API_KEY="ollama"

# 3. Smoke-test claw directly (this is what Jarvis will spawn per turn).
bash ../../scripts/jarvis-bridge.sh "summarize this repository"

# 4. Install OpenJarvis and copy the example config in.
cd /path/to/openjarvis && uv sync
mkdir -p ~/.openjarvis
cp /path/to/claw-code/examples/openjarvis/jarvis-config.toml ~/.openjarvis/config.toml

# 5. Drive claw through Jarvis.
uv run jarvis ask --agent claw_code "summarize this repository"
```

If the smoke test in step 3 returns clean JSON but step 5 fails, the
problem is on the OpenJarvis side (config path, agent registry, missing
branch). If step 3 itself fails, it's a `claw` problem — run
`claw doctor` for diagnostics.

## CPU-only? Use the ensemble

OpenJarvis ships [`scripts/claw_ensemble.py`][ensemble] alongside the
`claw_code` agent. It takes the same prompt and runs it across two or
more local models, with a quality gate that drops hallucinated tool
calls and empty replies. Two modes:

- **`cascade`** (default; best on CPU) — primary first, fallback only
  if the primary's reply trips the gate.
- **`race`** (best on GPU / multi-GPU) — every model concurrently,
  first clean reply wins.

```bash
ollama pull qwen2.5-coder:1.5b
ollama pull llama3.2:3b
export CLAW_ENSEMBLE_MODE=cascade
export CLAW_ENSEMBLE_MODELS="openai/qwen2.5-coder:1.5b,openai/llama3.2:3b"

uv run --directory /path/to/openjarvis \
  python scripts/claw_ensemble.py "write a fibonacci function in python"
```

Verified live on x86 CPU: warm turns return in ~10 s; the secondary
only spins up if the primary trips the filter.

[ensemble]: https://github.com/satan-stack/openjarvis/blob/claude/setup-jarvis-claw-code-7IWWT/scripts/claw_ensemble.py
