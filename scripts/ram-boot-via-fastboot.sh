#!/bin/bash
# RAM-boot a mainline boot.img via lk2nd fastboot, WITHOUT flashing anything.
# Uses only `fastboot boot`/`fastboot reboot` (never flash/flashall/unlock/update).
# Host-side fastboot needs root: set FASTBOOT="sudo fastboot" or run under sudo.
#
# Flow: adb-reboot into lk2nd fastboot -> wait for `fastboot devices` ->
# `fastboot boot <boot.img>`.
#
# Usage: ./ram-boot-via-fastboot.sh [/path/to/boot.img]
#   Defaults to /tmp/postmarketOS-export/boot.img (pmbootstrap export output).
#
# Env:
#   ADB_SERIAL       adb serial (default ec74ca69; from lib/adb-flash-common.sh)
#   FASTBOOT         fastboot binary (default: fastboot)
#   FASTBOOT_SERIAL  fastboot serial (default: $ADB_SERIAL)
#   FASTBOOT_WAIT    seconds to wait for fastboot to appear (default: 60)
#   SKIP_REBOOT=1    device is already in fastboot; skip the adb reboot step
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/adb-flash-common.sh
source "$SCRIPT_DIR/lib/adb-flash-common.sh"

FASTBOOT="${FASTBOOT:-fastboot}"
FASTBOOT_SERIAL="${FASTBOOT_SERIAL:-$ADB_SERIAL}"
FASTBOOT_WAIT="${FASTBOOT_WAIT:-60}"
BOOT_IMG="${1:-/tmp/postmarketOS-export/boot.img}"

[[ -f "$BOOT_IMG" ]] || { echo "Error: not a file: $BOOT_IMG" >&2; exit 1; }
BOOT_IMG="$(readlink -f "$BOOT_IMG" 2>/dev/null || echo "$BOOT_IMG")"

fb() {
	if [[ -n "$FASTBOOT_SERIAL" ]]; then
		"$FASTBOOT" -s "$FASTBOOT_SERIAL" "$@"
	else
		"$FASTBOOT" "$@"
	fi
}

if [[ "${SKIP_REBOOT:-0}" != "1" ]]; then
	if run_adb get-state >/dev/null 2>&1; then
		echo "Rebooting device (serial ${ADB_SERIAL:-default}) into lk2nd fastboot..."
		run_adb reboot bootloader || true
	else
		echo "No adb device; assuming it is already (or will be put) in fastboot." >&2
		echo "Put the phone into lk2nd fastboot now (power-button reboot)." >&2
	fi
fi

echo "Waiting up to ${FASTBOOT_WAIT}s for fastboot (serial ${FASTBOOT_SERIAL:-any})..."
for ((i = 0; i < FASTBOOT_WAIT; i++)); do
	if fb devices 2>/dev/null | grep -qiE 'fastboot'; then
		break
	fi
	sleep 1
done
fb devices 2>/dev/null | grep -qiE 'fastboot' || {
	echo "Error: no fastboot device after ${FASTBOOT_WAIT}s." >&2
	echo "Hold power to reboot into lk2nd fastboot, then re-run with SKIP_REBOOT=1." >&2
	exit 1
}

echo "RAM-booting $BOOT_IMG (no flash)..."
fb boot "$BOOT_IMG"
echo "Done. Watch misc stage1 log and USB gadget. Recover with: $FASTBOOT reboot"
