#!/bin/bash
# Rebuild the device-zte-p839f30 package after editing deviceinfo / initfs files:
# bump pkgrel, regenerate sha512sums, force build, install into the rootfs chroot,
# regenerate boot.img.
# Usage: ./scripts/rebuild-device-pkg.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${REPO_ROOT}/pmbootstrap_v3.cfg"
PMB=(pmbootstrap -c "$CFG" -p "$REPO_ROOT/pmaports")
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
"${PMB[@]}" export /tmp/postmarketOS-export

echo "Done. boot.img at /tmp/postmarketOS-export/boot.img — flash BOOT ONLY via TWRP:"
echo "  ./scripts/flash-partition.sh --target boot --offset-kb 512 --verify /tmp/postmarketOS-export/boot.img"
