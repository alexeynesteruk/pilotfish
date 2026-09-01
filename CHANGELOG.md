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

## v1.4.1 - 2026-09-01 (fork cleanup)

Forked from [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish)
at v1.4.1. Trimmed for personal use: removed the benchmark evidence suite,
the contributor test harness, translated docs, sponsorship links, and
upstream-only attribution/governance files. No change to the shipped policy,
role agents, or install runbooks beyond repointing repository URLs at this
fork.

For the full upstream history before the fork, see
[Nanako0129/pilotfish's CHANGELOG](https://github.com/Nanako0129/pilotfish/blob/main/CHANGELOG.md).
