#!/bin/bash
# Rebase our carried kernel commits onto a newer msm8916-mainline branch.
#
# Usage: ./update-linux.sh [--dry-run] <upstream-branch>
#   e.g. ./update-linux.sh wip/msm8916/7.3-rc1
#
# `origin` is our fork and carries the device branch; `upstream` is
# msm8916-mainline. The fork point is derived from what is not yet on any
# upstream branch, so nothing here needs updating when the base moves.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINUX="$REPO_ROOT/linux"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=1; shift; }
TARGET="${1:?Usage: $0 [--dry-run] <upstream-branch>}"

git -C "$LINUX" fetch --quiet upstream "$TARGET"

BRANCH=$(git -C "$LINUX" rev-parse --abbrev-ref HEAD)
mapfile -t CARRIED < <(git -C "$LINUX" rev-list HEAD --not --remotes=upstream)
[[ ${#CARRIED[@]} -gt 0 ]] || { echo "No carried commits; nothing to rebase." >&2; exit 1; }
BASE=$(git -C "$LINUX" rev-parse "${CARRIED[-1]}^")

cat <<EOF
Rebase carried kernel commits
  branch   : $BRANCH
  from     : $(git -C "$LINUX" describe --always "$BASE")
  onto     : upstream/$TARGET ($(git -C "$LINUX" rev-parse --short FETCH_HEAD))
  commits  : ${#CARRIED[@]}
EOF
git -C "$LINUX" log --reverse --format='    %h %s' "$BASE..HEAD"

[[ "$DRY_RUN" -eq 1 ]] && { echo "(dry run, nothing rebased)"; exit 0; }

git -C "$LINUX" rebase --onto FETCH_HEAD "$BASE" "$BRANCH"

echo "  kernel : $(make -C "$LINUX" -s kernelversion)"
echo "  head   : $(git -C "$LINUX" rev-parse --short HEAD)"
echo "Rebased. Push with: git -C linux push --force-with-lease origin $BRANCH"
