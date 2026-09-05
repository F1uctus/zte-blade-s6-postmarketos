#!/bin/bash
# Switch the active OS variant by flashing only its boot.img.
#
# Both rootfs images stay resident: the CLI variant on the `system` partition,
# Phosh on `userdata`. The boot partition holds whichever variant is active, and
# each variant's boot.img carries its own pmos_boot_uuid/pmos_root_uuid, so the
# initramfs mounts the matching rootfs.
#
# Usage: ./switch-variant.sh cli|phosh
# Env:   ADB_SERIAL=ec74ca69  VARIANT_DIR=/var/tmp/pmos-variants
#
# Device must be in TWRP. From a running system, get there with:
#   sudo python3 -c 'import ctypes; ctypes.CDLL(None).syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, b"recovery")'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VARIANT="${1:?Usage: $0 cli|phosh}"
VARIANT_DIR="${VARIANT_DIR:-/var/tmp/pmos-variants}"

case "$VARIANT" in
	cli|phosh) ;;
	*) echo "Error: variant must be 'cli' or 'phosh', got '$VARIANT'" >&2; exit 1 ;;
esac

BOOT_IMG="$VARIANT_DIR/$VARIANT/boot.img"
if [[ ! -f "$BOOT_IMG" ]]; then
	echo "Error: no boot.img for '$VARIANT' at $BOOT_IMG" >&2
	echo "Build it first: ./scripts/build-variant.sh $VARIANT" >&2
	exit 1
fi

echo "Switching to '$VARIANT' (flashing $(stat -c%s "$BOOT_IMG") bytes to boot)"
"$SCRIPT_DIR/flash-boot-via-adb.sh" "$BOOT_IMG"
echo
echo "Done. Reboot the device to start the '$VARIANT' variant."
