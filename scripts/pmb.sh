#!/bin/bash
# pmbootstrap against this repo's config and its aports submodule.
#
# Usage: ./scripts/pmb.sh <pmbootstrap args...>
#        PMB_CFG=pmbootstrap_phosh.cfg ./scripts/pmb.sh build ...
#
# The configs name no aports path, so every invocation supplies it from the
# repo root. Use this instead of calling pmbootstrap directly.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${PMB_CFG:-$REPO_ROOT/pmbootstrap_v3.cfg}"
[[ "$CFG" = /* ]] || CFG="$REPO_ROOT/$CFG"
[[ -f "$CFG" ]] || { echo "Error: no such config: $CFG" >&2; exit 1; }

# One pmbootstrap at a time: a second run zaps the shared chroot mounts and
# orphans the first. The lock is held on fd 9 across the exec below.
LOCK="${TMPDIR:-/var/tmp}/pmbootstrap-$(id -u).lock"
exec 9>"$LOCK"
if ! flock -n 9; then
	echo "Error: another pmbootstrap run holds $LOCK" >&2
	echo "  Wait for it, or set PMB_NOLOCK=1 if you know it has exited." >&2
	[[ "${PMB_NOLOCK:-0}" = 1 ]] || exit 1
fi

exec pmbootstrap -c "$CFG" -p "$REPO_ROOT/pmaports" "$@"
