#!/bin/bash
# Rebuild the device-zte-p839f30 package after editing deviceinfo / initfs files:
# bump pkgrel, regenerate sha512sums, force build, install into the rootfs chroot,
# regenerate boot.img.
# Usage: ./scripts/rebuild-device-pkg.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${REPO_ROOT}/pmbootstrap_v3.cfg"
PKGDIR="${REPO_ROOT}/pmaports/device/testing/device-zte-p839f30"
APKBUILD="${PKGDIR}/APKBUILD"

cur=$(grep -E '^pkgrel=' "$APKBUILD" | head -1 | cut -d= -f2)
next=$((cur + 1))
echo "Bumping pkgrel ${cur} -> ${next}"
sed -i "s/^pkgrel=${cur}/pkgrel=${next}/" "$APKBUILD"

echo "Regenerating checksums (deviceinfo, initfs hooks, etc.)..."
pmbootstrap -c "$CFG" checksum device-zte-p839f30

echo "Force-building device-zte-p839f30..."
pmbootstrap -c "$CFG" build --force device-zte-p839f30

echo "Installing device pkg into rootfs chroot (no UUID change)..."
pmbootstrap -c "$CFG" chroot -r -- apk add -u device-zte-p839f30 device-zte-p839f30-nonfree-firmware

echo "Regenerating boot.img (initfs build + export)..."
pmbootstrap -c "$CFG" initfs build
pmbootstrap -c "$CFG" export /tmp/postmarketOS-export

echo "Done. boot.img at /tmp/postmarketOS-export/boot.img — flash BOOT ONLY via TWRP:"
echo "  ADB_SERIAL=ec74ca69 ./scripts/flash-boot-via-adb.sh /tmp/postmarketOS-export/boot.img"
