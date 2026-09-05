#!/bin/bash
# Convert pmbootstrap's sparse zte-p839f30.img to a raw image for userdata dd.
# The full image contains GPT subpartitions (boot + root) required by initramfs
# (pmos_boot_uuid + pmos_root_uuid on the kernel cmdline).
#
# Usage: ./scripts/prepare-pmos-userdata-image.sh [sparse.img] [output.raw]
set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARSE="${1:-$HOME/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/zte-p839f30.img}"
OUT="${2:-/tmp/zte-p839f30-userdata.raw}"

if [[ ! -f "$SPARSE" ]]; then
	echo "Error: sparse image not found: $SPARSE" >&2
	exit 1
fi

echo "Converting sparse install image to raw (boot+root GPT container)..."
simg2img "$SPARSE" "$OUT"
echo "Userdata image: $OUT ($(stat -c%s "$OUT") bytes)"
fdisk -l "$OUT" 2>/dev/null | sed -n '1,12p' || true
blkid "$OUT" 2>/dev/null || true
