# pilotfish - Project Install Runbook

> This document is written for an AI agent (Claude Code) performing the installation in a user's project. If you are that agent: follow the steps in order, never skip the approval gate in Step 2, and prefer merging over overwriting at every point. A human can follow the same steps by hand.

pilotfish installs per project. Nothing is written to `~/.claude/`, no plugin is
registered, and no hook runs. Every installed file is plain text inside the
project you choose.

## What you are installing

| Target | Change |
|---|---|
| `<project>/.claude/agents/` | Eight role agent files: `scout.md`, `Explore.md`, `plan-verifier.md`, `security-reviewer.md`, `mech-executor.md`, `executor.md`, `verifier.md`, `security-executor.md` |
| `<project>/CLAUDE.md` | One `## Orchestration` section between `<!-- pilotfish:begin -->` and `<!-- pilotfish:end -->` markers |
| `<project>/.claude/settings.json` or `.claude/settings.local.json` | Optional: `model` and `fallbackModel` for this project only |

Source of truth for the files: the [templates/](../templates/) directory of this
repository. Run this install from a local clone and copy those files directly.

> **Portability:** Prefer your own Read / Write / Edit tools over shell commands for all file operations - they behave identically on macOS, Linux, WSL, and native Windows. The bash snippets below are references, not requirements.

## Step 0 - Resolve the project root

Ask the user which project to install into, or use the current working
directory when they already named it. Resolve it to an absolute path and use
that path verbatim as `$PROJECT` for the rest of this runbook:

```bash
cd /path/to/the/project && pwd
```

Confirm it is the directory the user actually runs `claude` from. Claude Code
loads `CLAUDE.md` and `.claude/` relative to the session's working directory
tree, so installing into a sibling or parent directory silently installs
nothing that project's sessions will load.

Carry the resolved path into the Step 2 plan so the user can catch a wrong
project before anything is written.

## Step 1 - Preflight (read-only)

Gather the current state before proposing anything:

1. Run `claude --version` and parse its semantic version. pilotfish requires **Claude Code 2.1.219 or newer**. Older versions do not reliably enforce agent `tools` allowlists, and `plan-verifier` and `security-reviewer` depend on enforced tool exclusion to preserve their read-only boundary. If the command is unavailable, its version cannot be parsed, or it reports an older version, **stop before presenting a write plan** and ask the user to update Claude Code.
2. Read `$PROJECT/CLAUDE.md` if it exists. Check for existing `<!-- pilotfish:begin -->` / `<!-- pilotfish:end -->` markers - their presence means this is an **upgrade**, not a fresh install.
3. List `$PROJECT/.claude/agents/` and note which of the eight pilotfish filenames already exist. **Also read the `name:` frontmatter of every existing agent file (any filename)** - Claude Code resolves collisions by the `name` field, not the filename, and loads only one definition per name. If any existing agent already declares `name: scout`, `Explore`, `plan-verifier`, `security-reviewer`, `mech-executor`, `executor`, `verifier`, or `security-executor`, flag the collision in the plan and ask the user whether to rename theirs, skip that pilotfish role, or overwrite.
4. Note any same-name agents at user level (`~/.claude/agents/`) or from an enabled plugin. A project-level file takes precedence for sessions in this project; report the shadowing in your summary so the user is not surprised elsewhere.
5. Read `$PROJECT/.claude/settings.json` and `$PROJECT/.claude/settings.local.json` if present (note any existing `model`, `fallbackModel`, `availableModels`).
6. Check whether the environment variable `CLAUDE_CODE_SUBAGENT_MODEL` is set, in the shell and in the `env` block of any settings file (`echo "$CLAUDE_CODE_SUBAGENT_MODEL"`).
7. Check whether the project is a Git repository and whether `.claude/` is git-ignored. This decides the Step 3.4 recommendation.

> **`CLAUDE_CODE_SUBAGENT_MODEL`:** on Claude Code 2.1.252 this variable sets the model for subagents that declare **no** `model:` frontmatter; it does **not** override a role that declares one. Measured directly: with `CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5`, `scout` (`model: haiku`) ran on `claude-haiku-4-5` while a control agent with no `model:` field ran on `claude-sonnet-5`, in the same session. All eight pilotfish roles declare a model, so a set variable does not break the tiering.
>
> Report the value in your plan anyway, for two reasons: it silently changes every *other* subagent in the user's setup, and older Claude Code versions documented the opposite precedence. Do not unset it without approval.

## Step 2 - Present the plan and get approval

State the resolved `$PROJECT` from Step 0 above the table, then show the user a
table of every change you intend to make: each file, the exact modification,
and whether it is a create / merge / replace-between-markers / skip. Include
the backup line (Step 3.1) and the Step 3.4 shared-versus-personal decision.
**Do not write anything until the user approves.**

## Step 3 - Apply

### 3.1 Backup and directories

Only `CLAUDE.md` and an existing settings file need backing up; the eight agent
files are new paths in a fresh install and are diffed individually on upgrade.

```bash
set -eu

PROJECT=$(pwd)                              # Step 0, verified
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$PROJECT/.claude/agents" "$PROJECT/.claude/backups"

pilotfish_backup_file() {
  BACKUP_SOURCE=$1
  BACKUP_FINAL=$2
  BACKUP_LABEL=$3
  if [ -L "$BACKUP_SOURCE" ] || [ ! -f "$BACKUP_SOURCE" ]; then
    echo "Stop: $BACKUP_LABEL must be a regular file." >&2
    exit 1
  elif [ -e "$BACKUP_FINAL" ] || [ -L "$BACKUP_FINAL" ]; then
    echo "Stop: backup destination already exists: $BACKUP_FINAL" >&2
    exit 1
  fi
  cp -p "$BACKUP_SOURCE" "$BACKUP_FINAL" || {
    echo "Stop: $BACKUP_LABEL backup copy failed." >&2
    exit 1
  }
  if [ ! -f "$BACKUP_FINAL" ] || ! cmp -s "$BACKUP_SOURCE" "$BACKUP_FINAL"; then
    rm -f "$BACKUP_FINAL"
    echo "Stop: $BACKUP_LABEL backup verification failed." >&2
    exit 1
  fi
}

if [ -e "$PROJECT/CLAUDE.md" ] || [ -L "$PROJECT/CLAUDE.md" ]; then
  pilotfish_backup_file "$PROJECT/CLAUDE.md" \
    "$PROJECT/.claude/backups/CLAUDE.md.pilotfish-$STAMP" CLAUDE.md
fi
```

This block must exit `0` before Steps 3.2-3.4 may begin. If an existing source
cannot be copied and read-back verified, stop and do not change agent files or
`CLAUDE.md`. Backups land in `.claude/backups/` rather than the repository root;
tell the user the exact path, and offer to git-ignore that directory so a
backup is never committed by accident.

### 3.2 Agent files

For each of the eight files in `templates/agents/`, write it to
`$PROJECT/.claude/agents/<same-name>.md`:

| Existing state | Action |
|---|---|
| File doesn't exist, no `name:` collision (Step 1.3) | Write it |
| File exists, identical content | Skip (report as up-to-date) |
| File exists, different content | Show the diff, ask: overwrite (upgrade) or keep theirs |
| A *different* file declares the same `name:` | Stop and ask (see Step 1.3) - never install a second file with a duplicate `name` |

> **Note:** The project-level agent named `Explore` intentionally shadows Claude Code's built-in Explore subagent for this project, pinning exploration to Haiku instead of letting it inherit the main-session model. This is expected, not a conflict.

### 3.3 CLAUDE.md policy section

The canonical section content is
[templates/claude-md.orchestration.md](../templates/claude-md.orchestration.md) -
it already includes the begin/end markers.

Before writing, count the markers: `grep -c "pilotfish:begin" "$PROJECT/CLAUDE.md"`.
The count must be `0` (fresh) or `1` (upgrade).

| Marker count | Action |
|---|---|
| File missing | Create it with the section as its content |
| `0` | Append the section at the end (or after the first `#` heading if the file has one - either is fine) |
| `1` | Replace exactly that one block, from its `<!-- pilotfish:begin -->` through its matching `<!-- pilotfish:end -->` inclusive (idempotent upgrade) |
| `>1` | **Stop and ask the user** - do not blind-replace; a greedy first-begin-to-last-end replacement could delete user content sitting between two marker pairs |

Do not modify anything outside the markers.

### 3.4 Model settings (optional, and a sharing decision)

pilotfish routes each role through its own agent frontmatter, so the roles work
regardless of the main-session model. Pinning the main session to Opus is a
separate, optional choice with three paths - ask the user which they want and
never pick for them:

| Path | Where | Who it affects |
|---|---|---|
| Personal, per project | `$PROJECT/.claude/settings.local.json` | Only this user, in this project. Usually git-ignored. **Recommended default.** |
| Shared with the team | `$PROJECT/.claude/settings.json` | Everyone who clones the repo. Only with explicit consent - it changes teammates' model and spend. |
| Nothing persisted | none | The user runs `/model opus` per session, or launches with `claude --model opus` |

When a settings file is chosen, merge only these keys and preserve everything
else in the file:

| Key | Rule |
|---|---|
| `model` | If absent → set `"opus"`. If present and different → **ask** before replacing; never overwrite an existing `fable`, `best`, full model ID, or other deliberate choice. |
| `fallbackModel` | If absent → add `["sonnet"]` (handles primary-model overload/unavailability; it does not fire on auth, billing, or rate-limit errors). If present → leave it and note it. |
| `availableModels` | **Only if the key already exists** (it is an allowlist): ensure it contains `"opus"`, `"sonnet"`, `"haiku"`, and the chosen main-model value. If absent → do not add it. |

Validate afterwards: `jq empty "$PROJECT/.claude/settings.json"` (or the
`.local.json` file you edited). A reference snippet is in
[templates/settings.snippet.json](../templates/settings.snippet.json).

If the project is a Git repository and the user chose the personal path, check
that `.claude/settings.local.json` is git-ignored; offer to add it if not.

## Step 4 - Verify and hand off

1. Every path you wrote is under the `$PROJECT` resolved in Step 0. Re-check it against your Step 2 plan; the checks below inspect whichever directory you wrote to, so they pass either way.
2. `ls "$PROJECT/.claude/agents/"` shows all eight files.
3. The markers appear exactly once: `grep -c "pilotfish:begin" "$PROJECT/CLAUDE.md"` prints `1`.
4. If a settings file was edited, `jq empty` on it exits 0.
5. Read the installed policy block and verify it says named roles are invoked without `model`, while only truly ad-hoc agents with no named role definition receive an explicit invocation model.
6. Tell the user to **start a new Claude Code session in that project**: the agents directory and project memory are read at session start. After restart, asking Claude "which subagent types are available?" should list the eight roles (scout, Explore, plan-verifier, security-reviewer, mech-executor, executor, verifier, security-executor).
7. Summarize what changed, what was skipped, whether anything was shadowed at user level, and where the backup is.

## Updating an existing install

When the user asks to **update** rather than fresh-install:

1. Detect the installed version: search `$PROJECT/CLAUDE.md` for `pilotfish v` inside the marker block; a comment like `<!-- pilotfish v2.0.0 -->` gives the installed version.
2. Compare against `VERSION` at the root of this checkout. If already current, say so and stop.
3. Otherwise re-run Steps 1-4. The install is idempotent: unchanged files are skipped, the policy block is replaced in place, and settings keys are only touched if missing.
4. If the user customized any agent file, the Step 3.2 diff surfaces it - never overwrite a customization without showing the diff and asking.

## Uninstall

On request, reverse the targets in this project only:

1. Delete the eight files from `$PROJECT/.claude/agents/` (only ones whose content matches pilotfish templates - show a diff first if they were customized). Remove `.claude/agents/` itself only if it is now empty.
2. Remove the block from `<!-- pilotfish:begin -->` through `<!-- pilotfish:end -->` (inclusive) in `$PROJECT/CLAUDE.md`; delete the file only if that leaves it empty and the user confirms.
3. In the settings file that was edited: remove `model` and `fallbackModel` if pilotfish added them, or restore prior values from the Step 3.1 backup. Leave `availableModels` additions unless asked - they are harmless.

Because everything lives inside the project, deleting the checkout or the
`.claude/` directory also fully removes pilotfish from that project. No global
state is left behind.
