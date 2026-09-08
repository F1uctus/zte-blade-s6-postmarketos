#!/bin/bash
# Build lk2nd, then flash lk2nd.img to boot partition via adb (TWRP) and verify.
# Device must be in TWRP, connected with adb. No fastboot required.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LK2ND_DIR="$REPO_ROOT/lk2nd"
LK2ND_IMG="${LK2ND_IMG:-$LK2ND_DIR/build-lk2nd-msm8916/lk2nd.img}"
TOOLCHAIN_PREFIX="${TOOLCHAIN_PREFIX:-arm-none-eabi-}"
LK2ND_COMPATIBLE="${LK2ND_COMPATIBLE:-zte,blade-s6}"
LK2ND_DISPLAY="${LK2ND_DISPLAY:-td4291_jdi_720p_video}"
LK2ND_FORCE_FASTBOOT="${LK2ND_FORCE_FASTBOOT:-0}"
# ms before the lk2nd menu auto-selects Recovery; 0/empty to disable.
LK2ND_MENU_AUTO_RECOVERY_MS="${LK2ND_MENU_AUTO_RECOVERY_MS:-5000}"

DRY_RUN=0
[[ "${1:-}" == --dry-run ]] && DRY_RUN=1
if (( DRY_RUN )); then
	cat <<EOF
Flash lk2nd
  source : $LK2ND_IMG (build from $LK2ND_DIR)
  target : boot at 0 KiB
  writes : lk2nd image
  checks : written-extent md5
EOF
	exit 0
fi
MAKE_ARGS=(
	TOOLCHAIN_PREFIX="$TOOLCHAIN_PREFIX"
	LK2ND_COMPATIBLE="$LK2ND_COMPATIBLE"
	LK2ND_DISPLAY="$LK2ND_DISPLAY"
	LK2ND_FORCE_FASTBOOT="$LK2ND_FORCE_FASTBOOT"
)
if [[ -n "$LK2ND_MENU_AUTO_RECOVERY_MS" ]] && [[ "$LK2ND_MENU_AUTO_RECOVERY_MS" != "0" ]]; then
	MAKE_ARGS+=(LK2ND_MENU_AUTO_RECOVERY_MS="$LK2ND_MENU_AUTO_RECOVERY_MS")
fi
BUILD_LOG=$(mktemp "${TMPDIR:-/var/tmp}/lk2nd-build.XXXXXX")
trap 'rm -f "$BUILD_LOG"' EXIT
if ! make -C "$LK2ND_DIR" "${MAKE_ARGS[@]}" lk2nd-msm8916 >"$BUILD_LOG" 2>&1; then
	cat "$BUILD_LOG" >&2
	exit 1
fi
rm -f "$BUILD_LOG"
trap - EXIT

[[ ! -f "$LK2ND_IMG" ]] && { echo "Error: lk2nd image not found: $LK2ND_IMG"; exit 1; }

exec "$SCRIPT_DIR/flash-partition.sh" --target boot --offset-kb 0 --verify "$LK2ND_IMG"
