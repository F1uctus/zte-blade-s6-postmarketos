#!/bin/bash
# Build one OS variant and stash its boot.img + rootfs image per variant.
#
#   cli   -> minimal console, rootfs lives on the `system` partition
#   phosh -> Phosh GUI, rootfs lives on `userdata`
#
# Usage: ./build-variant.sh cli|phosh [--flash-rootfs]
# Env:   ADB_SERIAL=ec74ca69  VARIANT_DIR=/var/tmp/pmos-variants  PMB_USER_PASSWORD=pmos
#
# --flash-rootfs writes the rootfs to that variant's partition (device in TWRP).
# Without it, only the images are built and stashed; switch-variant.sh then
# activates a variant by flashing its boot.img alone.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VARIANT="${1:?Usage: $0 cli|phosh [--flash-rootfs]}"
FLASH_ROOTFS=0
[[ "${2:-}" == "--flash-rootfs" ]] && FLASH_ROOTFS=1

case "$VARIANT" in
	cli)   CFG="$REPO_ROOT/pmbootstrap_v3.cfg";    TARGET_PART="system" ;;
	phosh) CFG="$REPO_ROOT/pmbootstrap_phosh.cfg"; TARGET_PART="userdata" ;;
	*) echo "Error: variant must be 'cli' or 'phosh', got '$VARIANT'" >&2; exit 1 ;;
esac

VARIANT_DIR="${VARIANT_DIR:-/var/tmp/pmos-variants}"
OUT="$VARIANT_DIR/$VARIANT"
EXPORT_DIR="/tmp/postmarketOS-export-$VARIANT"
export PMB_USER_PASSWORD="${PMB_USER_PASSWORD:-pmos}"
PMB=(pmbootstrap -y -c "$CFG")

# Both configs share chroot_rootfs_zte-p839f30, so --zap keeps one variant's
# rootfs out of the other. --no-recommends holds each to what it needs.
# abuild requires sha512sums that match the current deviceinfo.
echo "=== Refreshing device package checksums ==="
"${PMB[@]}" checksum device-zte-p839f30

echo "=== Building '$VARIANT' (rootfs target: $TARGET_PART) ==="
"${PMB[@]}" install --zap --no-recommends --password="$PMB_USER_PASSWORD"
"${PMB[@]}" export "$EXPORT_DIR"

mkdir -p "$OUT"
cp -L "$EXPORT_DIR/boot.img" "$OUT/boot.img"
echo "Stashed $OUT/boot.img"

# Copy by value: export leaves a symlink into chroot_native, which --zap deletes.
cp -L "$EXPORT_DIR/zte-p839f30.img" "$OUT/rootfs.img"
ROOTFS_IMG="$OUT/rootfs.img"
echo "$TARGET_PART" > "$OUT/target-partition"
echo "Stashed $ROOTFS_IMG -> partition '$TARGET_PART'"

if [[ "$FLASH_ROOTFS" = "1" ]]; then
	echo "=== Flashing rootfs to '$TARGET_PART' (device must be in TWRP) ==="
	USERDATA_BLOCK="$("$SCRIPT_DIR"/resolve-partition.sh "$TARGET_PART")" \
		"$SCRIPT_DIR/flash-rootfs-via-adb.sh" --verify "$ROOTFS_IMG"
fi

echo
echo "Done. Activate with: ./scripts/switch-variant.sh $VARIANT"
