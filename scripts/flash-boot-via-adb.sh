#!/bin/bash
# Flash a boot image to the boot partition over adb, device in TWRP.
#
# Usage: ./flash-boot-via-adb.sh [--verify] [--dry-run] /path/to/boot.img
# Env:   ADB_SERIAL=ec74ca69  LK2ND_OFFSET_KB=512  BOOT_BLOCK=/dev/block/...
#
# Offset 512 KiB is our pmOS boot.img; offset 0 is lk2nd.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/adb-flash-common.sh
source "$SCRIPT_DIR/lib/adb-flash-common.sh"

OFFSET_KB="${LK2ND_OFFSET_KB:-512}"
VERIFY=0
DRY_RUN=0
while [[ "${1:-}" == --* ]]; do
	case "$1" in
		--verify)  VERIFY=1 ;;
		--dry-run) DRY_RUN=1 ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
	shift
done
BOOT_IMG="${1:?Usage: $0 [--verify] [--dry-run] /path/to/boot.img}"
[[ -f "$BOOT_IMG" ]] || { echo "Not a file: $BOOT_IMG" >&2; exit 1; }
BOOT_IMG="$(readlink -f "$BOOT_IMG")"

IMG_SIZE=$(stat -c%s "$BOOT_IMG")
BLOCKS=$(( (IMG_SIZE + 4095) / 4096 ))
SEEK=$(( (OFFSET_KB * 1024) / 4096 ))

# Meaningful only when the payload is a compressed Linux image; lk2nd's is not.
kernel_is_gzip() {
	python3 - "$1" <<'PY' 2>/dev/null
import sys, struct
d = open(sys.argv[1], 'rb').read(4096)
if d[:8] != b'ANDROID!':
    sys.exit(1)
ksz, _, _, _, _, _, _, page = struct.unpack_from('<8I', d, 8)
sys.exit(0 if open(sys.argv[1], 'rb').read(page + 2)[page:page + 2] == b'\x1f\x8b' else 1)
PY
}
GZIP_CHECK=0
if [[ "${NO_GZIP_VERIFY:-0}" != "1" ]] && command -v python3 >/dev/null && kernel_is_gzip "$BOOT_IMG"; then
	GZIP_CHECK=1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
	BOOT_BLOCK="${BOOT_BLOCK:-$(resolve_boot_block 2>/dev/null || echo /dev/block/mmcblk0p21)}"
else
	check_adb_device
	BOOT_BLOCK="${BOOT_BLOCK:-$(resolve_boot_block)}"
fi

checks=""
[[ "$VERIFY" -eq 1 ]] && checks+=" byte-compare"
[[ "$GZIP_CHECK" -eq 1 ]] && checks+=" kernel-gzip"
cat <<EOF
Flash boot image
  source : $BOOT_IMG ($IMG_SIZE bytes)
  target : $BOOT_BLOCK at ${OFFSET_KB} KiB
  device : ${ADB_SERIAL:-default}
  checks :${checks:- none}
EOF
[[ "$DRY_RUN" -eq 1 ]] && { echo "(dry run, nothing written)"; exit 0; }

REMOTE=/tmp/flash_boot.img
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; run_adb shell "rm -f $REMOTE" >/dev/null 2>&1 || true' EXIT

run_adb push "$(adb_push_path "$BOOT_IMG")" "$REMOTE" >/dev/null 2>&1
run_adb shell "dd if=$REMOTE of=$BOOT_BLOCK bs=4096 seek=$SEEK conv=notrunc 2>/dev/null && sync"

# One read-back serves both checks.
if [[ "$VERIFY" -eq 1 || "$GZIP_CHECK" -eq 1 ]]; then
	run_adb exec-out "dd if=$BOOT_BLOCK bs=4096 skip=$SEEK count=$BLOCKS 2>/dev/null" > "$WORK/readback"
fi

if [[ "$VERIFY" -eq 1 ]]; then
	if head -c "$IMG_SIZE" "$WORK/readback" | cmp -s - "$BOOT_IMG"; then
		echo "  byte-compare: ok"
	else
		echo "  byte-compare: FAILED - partition differs from image" >&2
		exit 1
	fi
fi

if [[ "$GZIP_CHECK" -eq 1 ]]; then
	if python3 - "$WORK/readback" <<'PY'
import sys, struct, zlib
d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'ANDROID!', "bad boot header on device"
ksz, _, _, _, _, _, _, page = struct.unpack_from('<8I', d, 8)
blob = d[page:page + ksz]
i = blob.find(b'\xd0\x0d\xfe\xed')          # appended DTB, if any
z = zlib.decompressobj(16 + zlib.MAX_WBITS)
n = sum(len(z.decompress(c)) for c in
        [(blob[:i] if i > 0 else blob)[o:o + 65536]
         for o in range(0, len(blob[:i] if i > 0 else blob), 65536)]) + len(z.flush())
assert n > 20_000_000, f"kernel decompressed to only {n} bytes"
PY
	then
		echo "  kernel-gzip: ok"
	else
		echo "  kernel-gzip: FAILED - on-device kernel does not decompress" >&2
		exit 1
	fi
fi

echo "Done. Reboot to use it."
