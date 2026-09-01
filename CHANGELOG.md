# Changelog

All notable changes to this fork. The installed version is stamped inside the
policy block in the project's `CLAUDE.md` (`<!-- pilotfish vX.Y.Z -->`).

## v2.0.0 - 2026-09-01 (project scope)

**Breaking: pilotfish now installs per project instead of globally.**

Install targets moved from the Claude Code configuration root to the project:

| Was | Now |
|---|---|
| `~/.claude/agents/*.md` | `<project>/.claude/agents/*.md` |
| `~/.claude/CLAUDE.md` policy block | `<project>/CLAUDE.md` policy block |
| `~/.claude/settings.json` model pin | `<project>/.claude/settings.local.json` (optional) |

Removed with the global design:

- The Claude Code Plugin beta (`plugin/`, `.claude-plugin/marketplace.json`,
  `install/PLUGIN-INSTALL.md`), including its SessionStart hook. That hook was
  the only executable in the repository; no shell now runs at session start.
- `CLAUDE_CONFIG_DIR` resolution, migration, and legacy-coexistence handling,
  all of which existed only because the install was global.
- `install/AGENT-INSTALL.md`, replaced by `install/PROJECT-INSTALL.md`.

Other changes:

- `install/ACTIVATION-INSTALL.md` rewritten for a project-scoped
  `.claude/skills/pilotfish/SKILL.md`; the PATH-resident CLI wrapper is gone
  because it was inherently global.
- `templates/agents/security-reviewer.md` gained the outbound-egress warning
  that previously existed only in the plugin copy of that role: it holds
  `WebSearch` and `WebFetch` while reviewing security-sensitive code.
- The install runbook now makes the shared-versus-personal decision explicit,
  since `.claude/` and `CLAUDE.md` are normally committed and would otherwise
  change teammates' model routing and spend.

Verified by installing into a scratch project on Claude Code 2.1.252, macOS:

| Behavior | Evidence |
|---|---|
| All eight roles load from `.claude/agents/` | They appear as `subagent_type` values in a session started in that project |
| A project `Explore.md` shadows the built-in Explore | A sentinel string in the project file's description came back verbatim |
| A project `.claude/settings.local.json` `model` beats the user-level `model` | Project pin `haiku` against a user-level `opus[1m]`: the run reported `claude-haiku-4-5` |
| Role frontmatter aliases still resolve under a full-model-ID `availableModels` allowlist | Main ran `claude-opus-5[1m]` while the dispatched `scout` ran `claude-haiku-4-5` |
| `CLAUDE_CODE_SUBAGENT_MODEL` does **not** override explicit `model:` frontmatter | With the variable forced to `claude-sonnet-5`: `scout` (`model: haiku`) ran `claude-haiku-4-5` and a control agent with no `model:` field ran `claude-sonnet-5`, in one session |

These are single-machine observations on one version, not general guarantees.

The last row corrects inherited upstream documentation, which stated that the
variable "silently overrides every per-agent `model` frontmatter and defeats
the entire tiering design." That was the documented resolution order as of July
2026; it is not the behavior measured on 2.1.252. Corrected in the install
runbook, `docs/usage.md`, `docs/design.md`, and flagged as superseded in the
historical research report.

## v1.4.1 - 2026-09-01 (fork cleanup)

Forked from [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish)
at v1.4.1. Trimmed for personal use: removed the benchmark evidence suite,
the contributor test harness, translated docs, sponsorship links, and
upstream-only attribution/governance files. No change to the shipped policy,
role agents, or install runbooks beyond repointing repository URLs at this
fork.

For the full upstream history before the fork, see
[Nanako0129/pilotfish's CHANGELOG](https://github.com/Nanako0129/pilotfish/blob/main/CHANGELOG.md).
