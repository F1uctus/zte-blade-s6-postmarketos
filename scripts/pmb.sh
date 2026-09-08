#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${PMB_CFG:-$REPO_ROOT/pmbootstrap_cli.cfg}"
[[ "$CFG" = /* ]] || CFG="$REPO_ROOT/$CFG"
[[ -f "$CFG" ]] || { echo "Error: no such config: $CFG" >&2; exit 1; }

LOCK="${TMPDIR:-/var/tmp}/pmbootstrap-$(id -u).lock"
exec 9>"$LOCK"
if ! flock -n 9; then
	echo "Error: another pmbootstrap run holds $LOCK" >&2
	echo "  Wait for it, or set PMB_NOLOCK=1 if you know it has exited." >&2
	[[ "${PMB_NOLOCK:-0}" = 1 ]] || exit 1
fi

exec pmbootstrap -c "$CFG" -p "$REPO_ROOT/pmaports" "$@"
