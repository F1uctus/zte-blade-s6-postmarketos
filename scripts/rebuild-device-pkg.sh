#!/bin/bash
# Rebuild the device-zte-p839f30 package after editing deviceinfo / initfs files:
# bump pkgrel, regenerate sha512sums, force build, install into the rootfs chroot,
# regenerate boot.img.
#
# Usage: ./scripts/rebuild-device-pkg.sh cli|phosh
#
# The boot.img this emits carries the pmos_boot_uuid / pmos_root_uuid of the
# rootfs currently in that variant's chroot. It boots only the rootfs already on
# the device if that rootfs came from the same chroot; after a `build-variant.sh
# --zap` the filesystems are new and both images have to go to the device
# together.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:?Usage: $0 cli|phosh}"
case "$VARIANT" in
	cli)   CFG="${REPO_ROOT}/pmbootstrap_v3.cfg" ;;
	phosh) CFG="${REPO_ROOT}/pmbootstrap_phosh.cfg" ;;
	*) echo "Error: variant must be 'cli' or 'phosh', got '$VARIANT'" >&2; exit 1 ;;
esac
EXPORT_DIR="/tmp/postmarketOS-export-$VARIANT"
PMB=(env "PMB_CFG=$CFG" "$REPO_ROOT/scripts/pmb.sh")
PKGDIR="${REPO_ROOT}/pmaports/device/testing/device-zte-p839f30"
APKBUILD="${PKGDIR}/APKBUILD"

cur=$(grep -E '^pkgrel=' "$APKBUILD" | head -1 | cut -d= -f2)
next=$((cur + 1))
echo "Bumping pkgrel ${cur} -> ${next}"
sed -i "s/^pkgrel=${cur}/pkgrel=${next}/" "$APKBUILD"

echo "Regenerating checksums (deviceinfo, initfs hooks, etc.)..."
"${PMB[@]}" checksum device-zte-p839f30

echo "Force-building device-zte-p839f30..."
"${PMB[@]}" build --force device-zte-p839f30

echo "Installing device pkg into rootfs chroot (no UUID change)..."
"${PMB[@]}" chroot -r -- apk add -u device-zte-p839f30 device-zte-p839f30-nonfree-firmware

echo "Regenerating boot.img (initfs build + export)..."
"${PMB[@]}" initfs build
"${PMB[@]}" export "$EXPORT_DIR"

echo "Done. boot.img at $EXPORT_DIR/boot.img — flash boot:"
echo "  ./scripts/flash-partition.sh --target boot --offset-kb 512 --verify $EXPORT_DIR/boot.img"
echo "Root UUID it expects: $(strings -a "$EXPORT_DIR/boot.img" | grep -oE 'pmos_root_uuid=[0-9a-f-]+' | head -1)"
