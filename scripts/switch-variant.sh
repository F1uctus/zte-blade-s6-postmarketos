#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VARIANT="${1:?Usage: $0 cli|phosh}"
VARIANT_DIR="${VARIANT_DIR:-/var/tmp/pmos-variants}"
DRY_RUN=0
[[ "${2:-}" == --dry-run ]] && DRY_RUN=1

case "$VARIANT" in
	cli|phosh) ;;
	*) echo "Error: variant must be 'cli' or 'phosh', got '$VARIANT'" >&2; exit 1 ;;
esac

BOOT_IMG="$VARIANT_DIR/$VARIANT/boot.img"
if (( DRY_RUN )); then
	cat <<EOF
Switch variant
  source : $BOOT_IMG
  target : boot at 512 KiB
  writes : $VARIANT boot image
  checks : written-extent md5, head-intact, kernel-gzip when applicable
EOF
	exit 0
fi
if [[ ! -f "$BOOT_IMG" ]]; then
	echo "Error: no boot.img for '$VARIANT' at $BOOT_IMG" >&2
	echo "Build it first: ./scripts/build-variant.sh $VARIANT" >&2
	exit 1
fi

"$SCRIPT_DIR/flash-partition.sh" --target boot --offset-kb 512 --verify "$BOOT_IMG"
echo "Done. Reboot the device to start the '$VARIANT' variant."
