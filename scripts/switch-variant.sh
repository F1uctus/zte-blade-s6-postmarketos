#!/bin/bash
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
