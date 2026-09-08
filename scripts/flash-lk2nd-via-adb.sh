#!/bin/bash
# Build lk2nd, then flash lk2nd.img to boot partition via adb (TWRP) and verify.
# Device must be in TWRP, connected with adb. No fastboot required.
set -e
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

echo "Building lk2nd-msm8916 (force_fastboot=$LK2ND_FORCE_FASTBOOT auto_recovery_ms=$LK2ND_MENU_AUTO_RECOVERY_MS)..."
MAKE_ARGS=(
	TOOLCHAIN_PREFIX="$TOOLCHAIN_PREFIX"
	LK2ND_COMPATIBLE="$LK2ND_COMPATIBLE"
	LK2ND_DISPLAY="$LK2ND_DISPLAY"
	LK2ND_FORCE_FASTBOOT="$LK2ND_FORCE_FASTBOOT"
)
if [[ -n "$LK2ND_MENU_AUTO_RECOVERY_MS" ]] && [[ "$LK2ND_MENU_AUTO_RECOVERY_MS" != "0" ]]; then
	MAKE_ARGS+=(LK2ND_MENU_AUTO_RECOVERY_MS="$LK2ND_MENU_AUTO_RECOVERY_MS")
fi
(cd "$LK2ND_DIR" && make "${MAKE_ARGS[@]}" lk2nd-msm8916)

[[ ! -f "$LK2ND_IMG" ]] && { echo "Error: lk2nd image not found: $LK2ND_IMG"; exit 1; }

echo "Flashing and verifying..."
# lk2nd goes at the start of the partition (offset 0)
exec "$SCRIPT_DIR/flash-partition.sh" --target boot --offset-kb 0 --verify "$LK2ND_IMG"
