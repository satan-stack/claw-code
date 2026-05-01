# OpenJarvis integration

[OpenJarvis][oj] is a local-first personal-AI framework from Stanford's
Scaling Intelligence Lab. It exposes a registry of agents (orchestrator,
deep_research, monitor_operative, etc.) and a `code-assistant` preset for
day-to-day coding work.

[oj]: https://github.com/satan-stack/openjarvis

OpenJarvis already shipped a `claude_code` agent that wraps the Node.js
Claude Agent SDK. The companion `claw_code` agent (added in OpenJarvis
branch `claude/setup-jarvis-claw-code-7IWWT`) wraps **this** repository's
`claw` Rust CLI instead, removing the Node dependency and unlocking every
provider `claw` already speaks (Anthropic direct, xAI, OpenAI-compatible,
OpenRouter, Ollama, DashScope/Qwen, any Anthropic-compatible local proxy).

The same branch also adds `claw_smart`, a token-saving router on top of
`claw_code` that runs `qwen2.5-coder:1.5b` first and only escalates to
the requested Anthropic model when the local reply trips a quality
gate. `opus` goes straight to Anthropic (no useful local equivalent).

This document is the user-facing setup guide for the integration from
the `claw-code` side.

## At a glance

```
+---------------------+        spawns        +-------------------+        HTTP        +------------------+
|  jarvis ask ...     |  -----------------> |  claw prompt ...  |  ----------------> |  Model provider  |
|  (OpenJarvis CLI)   |  <----------------- |  (this repo)      |  <---------------- |  (Anthropic, ...) |
+---------------------+   JSON on stdout    +-------------------+                    +------------------+
```

OpenJarvis owns scheduling, telemetry, traces, channel adapters, and the
broader agent fabric. `claw` owns the coding loop, tool use, sessions,
and the model HTTP wire. They are connected by a single subprocess
invocation per Jarvis turn:

```
claw --output-format json \
     --model <alias> \
     --permission-mode <mode> \
     [--allowedTools tool,tool] \
     [--resume <session>] \
     prompt "<the user's question>"
```

## 1. Build `claw`

```bash
git clone https://github.com/satan-stack/claw-code
cd claw-code/rust
cargo build --workspace --release
```

Pick up the binary at `rust/target/release/claw`. For day-to-day use put
it on `PATH` or install via Cargo:

```bash
cargo install --path crates/rusty-claude-cli --force
```

Run `claw doctor` once to confirm credentials and provider connectivity.

## 2. Install OpenJarvis

```bash
git clone https://github.com/satan-stack/openjarvis
cd openjarvis
uv sync
```

Follow [OpenJarvis's README][oj] for the Rust extension build and
local-engine setup. The `claw_code` agent itself does **not** need a
local engine — it forwards inference to `claw`.

## 3. Wire the agent

Copy [`examples/openjarvis/jarvis-config.toml`](../../examples/openjarvis/jarvis-config.toml)
to `~/.openjarvis/config.toml` and edit the model / permission fields.
The relevant block:

```toml
[agent]
default_agent = "claw_code"
max_turns = 1                       # claw drives its own internal loop

[agent.claw_code]
binary = "claw"                     # or absolute path; CLAW_BINARY env wins
permission_mode = "workspace-write" # read-only | workspace-write | danger-full-access
allowed_tools = ["read", "glob", "edit"]
timeout = 300

[intelligence]
default_model = "sonnet"            # any alias claw understands
```

Then export the credential for whichever model `claw` should call — the
rules from [`USAGE.md`](../../USAGE.md#which-env-var-goes-where) apply
unchanged. Common cases:

```bash
export ANTHROPIC_API_KEY=sk-ant-...                    # Anthropic direct
export XAI_API_KEY=xai-...                             # Grok
export OPENAI_API_KEY=...   OPENAI_BASE_URL=...        # OpenRouter, Ollama, vLLM
export DASHSCOPE_API_KEY=sk-...                        # Qwen via DashScope
```

## 4. Run it

```bash
jarvis ask --agent claw_code "summarize this repository"
jarvis ask --agent claw_code "refactor src/auth.rs to use async/await"
jarvis ask --agent claw_code --model haiku "open issues that look like bugs"
```

Sessions land under `<workspace>/.claw/sessions/` exactly as if you were
calling `claw` directly. Resume one with:

```toml
[agent.claw_code]
resume = "latest"
```

## Token-saving cascade with `claw_smart`

The companion agent `claw_smart` routes Anthropic aliases through a
local model first, only spending Anthropic tokens on prompts the
local model can't answer cleanly:

| Asked model | Cascade chain                                       |
|-------------|-----------------------------------------------------|
| `haiku`     | `["openai/qwen2.5-coder:1.5b", "haiku"]`            |
| `sonnet`    | `["openai/qwen2.5-coder:1.5b", "sonnet"]`           |
| `opus`      | `["opus"]` — always Anthropic.                      |
| anything    | `[<as-is>]` — pass-through.                         |

```bash
ollama pull qwen2.5-coder:1.5b
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
export OPENAI_API_KEY="ollama"
export ANTHROPIC_API_KEY="sk-ant-..."   # only spent if qwen trips the filter

jarvis ask --agent claw_smart --model sonnet "..."   # qwen first
jarvis ask --agent claw_smart --model opus   "..."   # Anthropic direct
```

The winning result's metadata records the cascade trace under
`claw_smart_chain`, `claw_smart_winner`, and `claw_smart_attempts`,
so traces show exactly which step answered each turn. Verified live
on x86 CPU: a 14-token `sonnet` request landed entirely on qwen
(zero Anthropic tokens spent).

## How the bridge works

- OpenJarvis's `ClawCodeAgent` (in `src/openjarvis/agents/claw_code.py`)
  resolves the binary, spawns it with `--output-format json`, and parses
  the JSON object on stdout.
- The agent is registered as `"claw_code"` in OpenJarvis's `AgentRegistry`
  via `@AgentRegistry.register("claw_code")`, so `jarvis ask --agent claw_code`
  and any preset that names it just work.
- The `engine` argument required by `BaseAgent` is accepted but unused;
  inference is owned by `claw`. Telemetry and traces still flow through
  Jarvis's event bus via `_emit_turn_start` / `_emit_turn_end`.
- Permission mode, allow-list, model, and `--resume` map 1:1 to `claw`
  CLI flags. `extra_args` is available for power users who need to
  forward additional flags as the CLI grows.
- Exit-code and `binary_missing` failures are surfaced as structured
  `AgentResult` errors instead of crashing the parent Jarvis turn.

## See also

- [`examples/openjarvis/`](../../examples/openjarvis/) — ready-to-copy
  preset, README, and a thin `claw` wrapper script.
- [`USAGE.md`](../../USAGE.md) — full `claw` CLI reference.
- [`PARITY.md`](../../PARITY.md) — current Rust-port parity status.
- OpenJarvis [`docs/integrations/claw-code.md`][oj-doc] — the same guide
  written from the OpenJarvis side, including the full Python
  configuration reference for `ClawCodeAgent`.

[oj-doc]: https://github.com/satan-stack/openjarvis/blob/claude/setup-jarvis-claw-code-7IWWT/docs/integrations/claw-code.md
