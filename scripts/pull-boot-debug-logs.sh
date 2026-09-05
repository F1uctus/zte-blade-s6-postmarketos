#!/bin/bash
# Pull lk2nd splash log and any postmarketOS boot artifacts visible from TWRP.
# Run after a failed mainline boot attempt (device in TWRP, adb root).
# Usage: ADB_SERIAL=ec74ca69 ./scripts/pull-boot-debug-logs.sh [output-dir]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/adb-flash-common.sh
source "$SCRIPT_DIR/lib/adb-flash-common.sh"

OUT_DIR="${1:-$REPO_ROOT}"
mkdir -p "$OUT_DIR"

check_adb_device

echo "=== lk2nd splash log (last 64 KiB) ==="
ADB="$ADB" ADB_SERIAL="$ADB_SERIAL" "$SCRIPT_DIR/pull-lk-log.sh" "$OUT_DIR" || true

echo "=== boot partition headers (lk2nd @0, boot.img @512 KiB) ==="
BOOT_BLOCK="$(resolve_boot_block)"
run_adb exec-out "dd if=$BOOT_BLOCK bs=512 count=1 2>/dev/null" > "$OUT_DIR/boot-head-0.bin"
run_adb exec-out "dd if=$BOOT_BLOCK bs=512 skip=1024 count=1 2>/dev/null" > "$OUT_DIR/boot-head-512k.bin"
strings "$OUT_DIR/boot-head-0.bin" "$OUT_DIR/boot-head-512k.bin" > "$OUT_DIR/boot-head-strings.txt" 2>/dev/null || true

echo "=== userdata ext4 UUID (must match pmos_root_uuid in boot.img cmdline) ==="
USERDATA_BLOCK="$(resolve_userdata_block)"
run_adb shell "tune2fs -l $USERDATA_BLOCK 2>/dev/null | grep -E 'Filesystem UUID|Last mounted|Filesystem state'" \
	| tr -d '\r' > "$OUT_DIR/userdata-tune2fs.txt" || true
cat "$OUT_DIR/userdata-tune2fs.txt"

echo "=== boot.img cmdline at 512 KiB ==="
strings "$OUT_DIR/boot-head-512k.bin" | grep -E 'earlycon|pmos_root_uuid|pmos_boot_uuid|pmos\.boot|pmos\.root' \
	> "$OUT_DIR/boot-cmdline-snippet.txt" 2>/dev/null || true
cat "$OUT_DIR/boot-cmdline-snippet.txt" 2>/dev/null || true

echo "=== postmarketOS initfs log (misc @ 16 KiB) ==="
echo "    stage-1 'PMOS stage1:' checkpoints localize where init.sh dies;"
echo "    'PMOS initfs' lines are the stage-2 device hook (only if boot reached init_2nd)."
MISC_BLOCK="$(resolve_block_device misc /dev/block/mmcblk0p26)"
run_adb exec-out "dd if=$MISC_BLOCK bs=1 skip=16384 count=8192 2>/dev/null" \
	| tr -d '\0' > "$OUT_DIR/pmos-initfs-misc.log" 2>/dev/null || true
grep -a 'PMOS stage1:\|PMOS initfs' "$OUT_DIR/pmos-initfs-misc.log" 2>/dev/null \
	|| echo "  (no PMOS checkpoints in misc — init died before/at mount_proc_sys_dev, or kernel panicked pre-init)"

echo "=== nested GPT on userdata (first 512 B of p30p1/p30p2 if present) ==="
run_adb shell "for p in /dev/block/mmcblk0p30p1 /dev/block/mmcblk0p30p2; do
	[ -b \"\$p\" ] || continue
	echo \"--- \$p ---\"
	blkid \"\$p\" 2>/dev/null
done" | tr -d '\r' > "$OUT_DIR/userdata-subparts-blkid.txt" 2>/dev/null || true
cat "$OUT_DIR/userdata-subparts-blkid.txt" 2>/dev/null || true

echo "Done. Outputs in $OUT_DIR"
