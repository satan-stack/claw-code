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

# 2. Export a credential for the model claw should call.
export ANTHROPIC_API_KEY=sk-ant-...

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
