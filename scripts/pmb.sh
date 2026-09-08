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

exec pmbootstrap -c "$CFG" -p "$REPO_ROOT/pmaports" "$@"
