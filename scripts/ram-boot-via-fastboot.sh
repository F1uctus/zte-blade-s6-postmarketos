#!/bin/bash
# RAM-boot a boot.img through lk2nd's fastboot, writing nothing to the device.
# Uses only `fastboot boot`; the bootloader is locked and flash is refused.
#
# Usage: ./ram-boot-via-fastboot.sh [--dry-run] [/path/to/boot.img]
#   Defaults to /tmp/postmarketOS-export/boot.img.
#
# Env: FASTBOOT="sudo fastboot" when udev rules cover adb only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/transport.sh
source "$SCRIPT_DIR/lib/transport.sh"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=1; shift; }
BOOT_IMG="${1:-/tmp/postmarketOS-export/boot.img}"
[[ -f "$BOOT_IMG" ]] || { echo "Error: not a file: $BOOT_IMG" >&2; exit 1; }
BOOT_IMG="$(readlink -f "$BOOT_IMG")"

cat <<EOF
RAM-boot
  source : $BOOT_IMG ($(( $(stat -c%s "$BOOT_IMG") / 1048576 )) MiB)
  target : memory, nothing is written
EOF
[[ "$DRY_RUN" -eq 1 ]] && { echo "(dry run, nothing booted)"; exit 0; }

transport_detect
[[ "$TRANSPORT" == lk2nd-fastboot ]] || "$SCRIPT_DIR/enter-mode.sh" bootloader

_fb boot "$BOOT_IMG"
echo "Done. Recover with: ./scripts/enter-mode.sh system"
