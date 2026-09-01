# Local Qwen as an execution role

pilotfish's eight roles are Claude subagents. This document covers a ninth
execution route that is **not** a subagent: a local Qwen model driven by the
Qwen Code CLI, invoked by the main session through
[`bin/qwen-exec.sh`](../bin/qwen-exec.sh).

The point is cost asymmetry. Execution is the high-volume half of a coding
session, and on-prem tokens are free. The orchestrator keeps planning,
approval, integration, and judgment; a 27B local model does bounded, fully
specified implementation.

## Why a script instead of an agent file

A Claude Code subagent can only run models the session itself can reach. There
is no frontmatter that points one role at a different provider: redirecting the
session's base URL would move the orchestrator off Opus too, which is the
opposite of the design. So the Qwen executor is a Bash-invoked external CLI
that the main session calls, with the same discipline the subagent roles get:
a complete one-shot brief in, a mechanically checked diff out.

The installed policy block is unchanged by this. `qwen-exec.sh` slots into the
Execution gate as an alternative to `mech-executor` and `executor`; every other
gate (Plan, approval, `verifier`) behaves exactly as documented.

## Setup

```bash
npm install -g @qwen-code/qwen-code     # provides the `qwen` agentic loop
```

The script talks to the model two ways:

| `--endpoint` | Target | When |
|---|---|---|
| `gateway` (default) | `http://localhost:4000/v1`, model `qwen3.8-27b-local` | Normal use. Prometheus/Grafana see the traffic and LiteLLM serializes on the single llama.cpp slot. Needs `LITELLM_MASTER_KEY`. |
| `direct` | `http://192.168.0.98:8080/v1`, model `qwen3.8-27b-rvn-local` | Gateway down, or debugging. One less hop. |

Override with `QWEN_EXEC_GATEWAY`, `QWEN_EXEC_DIRECT`, `QWEN_EXEC_MODEL`.

## Use

```bash
bin/qwen-exec.sh \
  --spec brief.md \
  --scope "src/parse-duration.js" \
  --accept "node --test"
```

What it does, in order:

1. Preflights the endpoint, so an asleep machine fails immediately and clearly.
2. Creates a detached `git worktree` at current `HEAD`. The executor never sees
   the caller's working tree; the worst outcome is a directory to delete.
3. Runs `qwen --approval-mode yolo -p "$(cat brief.md)"` inside that worktree.
4. **Checks every changed path against `--scope`** and rejects on any file
   outside it, before acceptance runs. Passing tests cannot excuse drift.
5. Runs `--accept` inside the worktree and reports its exit code.
6. Emits a `.patch` and the worktree path. It never commits, merges, or pushes.

| Exit | Meaning |
|---|---|
| 0 | In scope, acceptance passed. Review the diff and apply. |
| 2 | Scope violation. Worktree kept for inspection. |
| 3 | In scope, acceptance failed. |
| 4 | Executor error. |
| 5 | No changes produced. |

After a rejected run, clean up with
`git -C <repo> worktree remove --force <printed worktree path>`.

## The brief is the whole job

Most cheap-model failures are spec failures. Use the same five fields the
subagent roles get: goal, constraints, done criteria, paths, rationale. The
done criteria must be a runnable command, because `--accept` is what decides
the outcome. If you cannot write a mechanical check for a task, it is not
delegatable yet - decompose further or keep it in the main session.

## Measured behavior (2026-09-01)

Endpoint: llama.cpp `b1-0b5be7e` serving `RVN-Q6_K-mtp.gguf`, 27.3B, `n_ctx`
131072, on an RTX 5090.

| Check | Result |
|---|---|
| Native tool calling | Works: `supports_tools`, parallel tool calls, `finish_reason: tool_calls`, correct arguments |
| Real task, direct endpoint | `slugify` against 4 tests: correct on first attempt, 25s |
| Real task, via gateway | `parseDuration` against 5 tests including a combined `1h30m` case: correct on first attempt, 2m50s |
| Scope enforcement | Rejected an in-scope-looking change when `--scope` excluded it, before acceptance ran |
| Test tampering | None observed: only the implementation file changed, tests untouched |

Two out of two first-pass successes is not a success rate. It is two data
points on small, fully specified, test-guarded tasks, which is exactly the task
shape this route is for.

## Limits worth knowing

- **One request at a time.** `llama-server` reports `total_slots: 1`, so there
  is no parallel executor fan-out. The gateway entry sets
  `max_parallel_requests: 1` to serialize where it is visible rather than
  letting requests queue invisibly inside llama.cpp.
- **`--approval-mode yolo` is real authority.** The executor's tool calls
  auto-execute at the calling process's privilege level. The worktree is
  isolation by convention, not a sandbox. Set `QWEN_SANDBOX=1` for qwen's own
  sandboxing where the platform supports it.
- **The machine can be asleep, so the pinned name matters.** The gateway has
  two entries pointing at this box. `qwen3.8-27b-local` has no failover at all,
  and that is what this script uses by default: a run either reaches the LAN
  box or fails loudly. The shared `qwen3.8-27b` group also has the box at
  order 1, but falls through to paid Groq behind it, so it is the convenient
  name and not a spend guarantee. Do not point executor batches at it.
- **No parallel fan-out, and the limit does not overflow.** `max_parallel_requests: 1`
  on the gateway entry serializes; measured, two concurrent calls were both
  served by the LAN box rather than one escalating to another provider. A batch
  of executor runs queues on the single slot.
- **Small `max_tokens` returns empty content.** The checkpoint is a reasoning
  model: it fills `reasoning_content` before `content`. A trivial prompt at
  `max_tokens: 25` came back with an empty answer and `finish_reason: length`.
  Budget for reasoning on top of the answer, and check `reasoning_content`
  before concluding the endpoint is broken. The Qwen Code harness sets its own
  budgets, so this bites direct API calls rather than `qwen-exec.sh`.
- **Long horizons are the weak spot, not syntax.** Published n=1 reports on
  local models of this class put tool-call format errors near 12% and describe
  cascade failures where the model keeps going after a subtask silently fails.
  That is what steps 4 and 5 exist to catch; keep tasks small enough that a
  single acceptance command can refute them.
