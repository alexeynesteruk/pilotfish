#!/usr/bin/env bash
# qwen-exec.sh - run a local Qwen model as a pilotfish execution role.
#
# The orchestrator writes a brief, this script runs it in a throwaway git
# worktree, then reports mechanically: which files changed, whether any fell
# outside the declared scope, and whether the acceptance command passed. It
# never merges, commits, or pushes - the orchestrator judges the diff.
#
# Usage:
#   qwen-exec.sh --spec BRIEF.md --scope "src/foo.js,src/bar.js" \
#                [--repo PATH] [--accept "npm test"] [--endpoint gateway|direct] [--keep]
#
# Exit codes: 0 accepted, 1 usage/preflight error, 2 scope violation,
#             3 acceptance failed, 4 executor error, 5 no changes produced.
set -euo pipefail

die() { printf 'qwen-exec: %s\n' "$1" >&2; exit "${2:-1}"; }

SPEC=""; SCOPE=""; REPO="$PWD"; ACCEPT=""; ENDPOINT="gateway"; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --spec) SPEC="${2:?}"; shift 2 ;;
    --scope) SCOPE="${2:?}"; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --accept) ACCEPT="${2:?}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:?}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$SPEC" ] || die "--spec is required"
[ -f "$SPEC" ] || die "spec file not found: $SPEC"
[ -n "$SCOPE" ] || die "--scope is required: an executor without a declared file scope cannot be checked"
command -v qwen >/dev/null 2>&1 || die "qwen CLI not on PATH (npm install -g @qwen-code/qwen-code)"

# Endpoint. The gateway gives Prometheus/Grafana visibility and serializes on
# the single llama.cpp slot; direct keeps working when the gateway is down.
case "$ENDPOINT" in
  gateway)
    BASE="${QWEN_EXEC_GATEWAY:-http://localhost:4000/v1}"
    KEY="${LITELLM_MASTER_KEY:-}"
    MODEL="${QWEN_EXEC_MODEL:-qwen3.8-27b-local}"
    [ -n "$KEY" ] || die "LITELLM_MASTER_KEY is unset; use --endpoint direct to bypass the gateway"
    ;;
  direct)
    BASE="${QWEN_EXEC_DIRECT:-http://192.168.0.98:8080/v1}"
    KEY="local-no-auth"
    MODEL="${QWEN_EXEC_MODEL_DIRECT:-qwen3.8-27b-rvn-local}"
    ;;
  *) die "--endpoint must be 'gateway' or 'direct'" ;;
esac

curl -fsS -m 10 "${BASE%/v1}/health" >/dev/null 2>&1 \
  || curl -fsS -m 10 -H "Authorization: Bearer $KEY" "$BASE/models" >/dev/null 2>&1 \
  || die "executor endpoint unreachable: $BASE (is the machine awake?)"

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $REPO"
BASE_SHA=$(git -C "$REPO" rev-parse HEAD)

# Isolated worktree at the current HEAD. The executor cannot see or touch the
# caller's working tree, so the worst outcome is a directory to delete.
WT=$(mktemp -d "${TMPDIR:-/tmp}/qwen-exec.XXXXXX")/wt
git -C "$REPO" worktree add --detach --quiet "$WT" "$BASE_SHA" \
  || die "could not create worktree (uncommitted state on a bare/odd repo?)"

cleanup() {
  if [ "$KEEP" -eq 0 ]; then
    git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf "$(dirname "$WT")"
  fi
}

printf 'qwen-exec: model=%s endpoint=%s\n' "$MODEL" "$BASE" >&2
printf 'qwen-exec: worktree=%s base=%s\n' "$WT" "${BASE_SHA:0:12}" >&2

# --approval-mode yolo auto-executes the executor's tool calls. That authority
# is confined to this worktree by convention, not by a sandbox: qwen runs at
# this process's privilege level. Set QWEN_SANDBOX=1 in the environment to add
# qwen's own sandboxing where the platform supports it.
set +e
( cd "$WT" && OPENAI_API_KEY="$KEY" OPENAI_BASE_URL="$BASE" OPENAI_MODEL="$MODEL" \
    QWEN_CODE_SUPPRESS_YOLO_WARNING=1 \
    qwen --approval-mode yolo -p "$(cat "$SPEC")" ) >"$WT.out" 2>"$WT.err"
QRC=$?
set -e
printf 'qwen-exec: executor exit=%s\n' "$QRC" >&2
[ "$QRC" -eq 0 ] || { sed -n '1,20p' "$WT.err" >&2; cleanup; exit 4; }

CHANGED=$(git -C "$WT" status --porcelain | sed 's/^...//' | sed 's/.* -> //')
if [ -z "$CHANGED" ]; then
  printf 'qwen-exec: executor produced no changes\n' >&2
  cleanup; exit 5
fi

# Mechanical scope enforcement. A cheap executor drifting into files nobody
# authorized is the failure this catches; it is not negotiable at review time.
VIOLATIONS=""
OLDIFS=$IFS
while IFS= read -r f; do
  [ -n "$f" ] || continue
  ok=0
  IFS=,
  for pat in $SCOPE; do
    pat=$(printf '%s' "$pat" | sed 's/^ *//;s/ *$//')
    # shellcheck disable=SC2254
    case "$f" in $pat) ok=1; break ;; esac
  done
  IFS=$OLDIFS
  [ "$ok" -eq 1 ] || VIOLATIONS="$VIOLATIONS$f
"
done <<EOF
$CHANGED
EOF
IFS=$OLDIFS

printf '\n--- files changed ---\n%s\n' "$CHANGED"

if [ -n "$VIOLATIONS" ]; then
  printf '\n--- SCOPE VIOLATION: files outside --scope ---\n%s\n' "$VIOLATIONS" >&2
  printf 'qwen-exec: rejecting; worktree kept at %s\n' "$WT" >&2
  exit 2
fi

ACC_RC=0
if [ -n "$ACCEPT" ]; then
  printf '\n--- acceptance: %s ---\n' "$ACCEPT"
  set +e
  ( cd "$WT" && eval "$ACCEPT" ) 2>&1 | tail -30
  ACC_RC=${PIPESTATUS[0]}
  set -e
  printf 'qwen-exec: acceptance exit=%s\n' "$ACC_RC" >&2
fi

printf '\n--- diff ---\n'
git -C "$WT" --no-pager diff --stat
git -C "$WT" --no-pager diff > "$WT.patch"
printf '\npatch: %s\n' "$WT.patch"
printf 'worktree: %s\n' "$WT"
printf 'apply with: git -C <repo> apply %s\n' "$WT.patch"

[ "$ACC_RC" -eq 0 ] || exit 3
exit 0
