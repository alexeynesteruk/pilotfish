# Optional: a `/pilotfish` activation shortcut

The policy block installed in the project's `CLAUDE.md` loads automatically for
every session in that project. This optional skill only saves you from retyping
the explicit activation sentence when you want the lifecycle applied to one
specific task. Install pilotfish with [PROJECT-INSTALL.md](./PROJECT-INSTALL.md)
first.

> **Claim boundary:** this is a deliberate user opt-in, not automatic dispatch. Higher-priority Claude Code instructions can still suppress Agent delegation.

## Choose an activation path

| Method | Input source | Notes |
|---|---|---|
| Paste the opt-in sentence | User prompt | No install needed; the reference path |
| Invoke `/pilotfish <task>` | [User-invocable skill](https://code.claude.com/docs/en/slash-commands#control-who-invokes-a-skill) with the task in `$ARGUMENTS` | Same text, one keystroke; installed per project |

The skill uses `disable-model-invocation: true`, so Claude cannot activate it
on your behalf - you choose when the lifecycle applies.

## Install

Create `<project>/.claude/skills/pilotfish/SKILL.md` with exactly these
contents. Inspect the path first and stop if a different skill already owns
that name; never overwrite an unowned file.

```markdown
---
name: pilotfish
description: Explicitly activate the installed pilotfish orchestration policy for one task.
argument-hint: "<task>"
disable-model-invocation: true
---

<!-- pilotfish-activation-skill -->

Use pilotfish. Follow its dispatch brake: keep direct work in the main session
and call the named agents only when the policy selects delegation.

Complete this task:

$ARGUMENTS

If no task was supplied, ask the user for it before starting work.
```

Because the skill lives under `.claude/`, it is shared with anyone who clones
the repository. Keep it out of a shared repo by adding that path to
`.gitignore` if you want it to stay personal.

## Use and verify

Claude Code supports [live skill change detection](https://code.claude.com/docs/en/slash-commands#live-change-detection).
Open `/skills` and confirm `pilotfish` is visible, or start a new session if the
current one does not pick it up. Invoke it at the start of a task:

```text
/pilotfish migrate the cache schema without changing the public API
```

Without the skill, the equivalent plain sentence is:

```text
Use pilotfish. Follow its dispatch brake: keep direct work in the main session
and call the named agents only when the policy selects delegation.
```

Either way this authorizes pilotfish to apply its dispatch brake; neither
requires delegation. Small or tightly coupled work may stay in the main
session, and higher-priority managed policy can still block Agent use.

## Remove

Delete `<project>/.claude/skills/pilotfish/SKILL.md` (and the now-empty
directory). Nothing else references it; the core install is unaffected.
