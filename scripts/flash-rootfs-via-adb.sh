#!/bin/bash
# Flash postmarketOS userdata image via adb (TWRP, root).
# Use the full install image (zte-p839f30.img/.raw), not a root-only ext4 dump.
# Usage: ./flash-rootfs-via-adb.sh [--verify] /path/to/zte-p839f30.{img,raw}
# Env: ADB_SERIAL=ec74ca69 USERDATA_BLOCK=/dev/block/mmcblk0p30
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/adb-flash-common.sh
source "$SCRIPT_DIR/lib/adb-flash-common.sh"

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
CHUNK_MIB_PREVIEW="${CHUNK_MIB:-512}"
ROOTFS_IMG="${1:?Usage: $0 [--verify] /path/to/zte-p839f30.img}"

[[ ! -f "$ROOTFS_IMG" ]] && { echo "Error: not a file: $ROOTFS_IMG"; exit 1; }

FLASH_IMG="$(readlink -f "$ROOTFS_IMG" 2>/dev/null || echo "$ROOTFS_IMG")"
TMP_RAW=""
cleanup() {
	[[ -n "$TMP_RAW" && -f "$TMP_RAW" ]] && rm -f "$TMP_RAW"
}
trap cleanup EXIT

if blkid "$FLASH_IMG" 2>/dev/null | grep -q 'TYPE="ext4"'; then
	echo "Warning: image looks like a single ext4 root partition." >&2
	echo "  Initramfs expects boot+root GPT inside userdata; use zte-p839f30.img instead." >&2
fi

[[ "$DRY_RUN" -eq 1 ]] || check_adb_device
USERDATA_BLOCK="${USERDATA_BLOCK:-$(resolve_userdata_block)}"

IMG_SIZE=$(stat -c%s "$FLASH_IMG" 2>/dev/null || stat -f%z "$FLASH_IMG")
PART_SIZE=$(run_adb shell "blockdev --getsize64 $USERDATA_BLOCK 2>/dev/null" 2>/dev/null | tr -d '\r')
[[ -n "$PART_SIZE" ]] || PART_SIZE=0
RAW_SIZE="$IMG_SIZE"
if file -b "$FLASH_IMG" | grep -q 'Android sparse'; then
	# sparse_header: blk_sz at offset 12, total_blks at offset 16. Reading
	# offset 12 as the block count made this evaluate to 4096*4096 = 16 MiB for
	# every image, so the oversize check below never actually fired.
	_blk_sz=$((0x$(od -An -tx4 -j12 -N4 "$FLASH_IMG" | tr -d ' ')))
	_total_blks=$((0x$(od -An -tx4 -j16 -N4 "$FLASH_IMG" | tr -d ' ')))
	RAW_SIZE=$((_blk_sz * _total_blks))
fi
if [[ "$PART_SIZE" =~ ^[0-9]+$ ]] && [[ "$PART_SIZE" -gt 0 ]] && [[ "$RAW_SIZE" -gt "$PART_SIZE" ]]; then
	echo "Error: image ($RAW_SIZE bytes raw) larger than $USERDATA_BLOCK ($PART_SIZE bytes)" >&2
	exit 1
fi

cat <<EOF
Flash rootfs image
  source : $FLASH_IMG
  target : $USERDATA_BLOCK ($(( PART_SIZE / 1048576 )) MiB partition)
  write  : $(( RAW_SIZE / 1048576 )) MiB in $(( (RAW_SIZE / 1048576 + CHUNK_MIB_PREVIEW - 1) / CHUNK_MIB_PREVIEW )) chunk(s) of ${CHUNK_MIB_PREVIEW} MiB
  device : ${ADB_SERIAL:-default}
  checks : per-chunk md5$([[ "$VERIFY" -eq 1 ]] && echo " + full-extent md5")
EOF
[[ "${DRY_RUN:-0}" -eq 1 ]] && { echo "(dry run, nothing written)"; exit 0; }

if file -b "$FLASH_IMG" | grep -q 'Android sparse'; then
	# Host simg2img (reliable); push raw via /internal_sd (TWRP /tmp is too small).
	# The raw image is ~1.5 GiB and /tmp is often tmpfs, so stage it on disk.
	TMP_RAW="$(mktemp "${TMPDIR:-/var/tmp}/zte-p839f30-userdata.XXXXXX.raw")"
	trap 'rm -f "$TMP_RAW"' EXIT
	echo "Converting Android sparse image to raw on host..."
	simg2img "$FLASH_IMG" "$TMP_RAW"
	FLASH_IMG="$TMP_RAW"
	IMG_SIZE=$(stat -c%s "$FLASH_IMG" 2>/dev/null || stat -f%z "$FLASH_IMG")
	:
fi

# Chunked: staging never exceeds CHUNK_MIB and a failure costs one chunk.
CHUNK_MIB="${CHUNK_MIB:-512}"
REMOTE_STAGING="${REMOTE_STAGING:-/internal_sd/pmos-flash}"
REMOTE_CHUNK="$REMOTE_STAGING/chunk.raw"
run_adb shell "mkdir -p $REMOTE_STAGING"

TOTAL_MIB=$(( (IMG_SIZE + 1048575) / 1048576 ))
CHUNKS=$(( (TOTAL_MIB + CHUNK_MIB - 1) / CHUNK_MIB ))
echo "Writing $TOTAL_MIB MiB to $USERDATA_BLOCK in $CHUNKS chunk(s) of $CHUNK_MIB MiB"

HOST_CHUNK="$(mktemp "${TMPDIR:-/var/tmp}/zte-chunk.XXXXXX")"
trap 'rm -f "$TMP_RAW" "$HOST_CHUNK"' EXIT

# The USB link drops during sustained transfers and adb push reports success on
# a truncated file, so hash each chunk on the device and retry until it matches.
PUSH_RETRIES="${PUSH_RETRIES:-4}"
for ((i = 0; i < CHUNKS; i++)); do
	off=$(( i * CHUNK_MIB ))
	dd if="$FLASH_IMG" of="$HOST_CHUNK" bs=1M skip="$off" count="$CHUNK_MIB" status=none
	want=$(md5sum "$HOST_CHUNK" | awk '{print $1}')
	printf '  chunk %d/%d (offset %d MiB) ... ' "$((i + 1))" "$CHUNKS" "$off"

	pushed=0
	for ((try = 1; try <= PUSH_RETRIES; try++)); do
		run_adb push "$(adb_push_path "$HOST_CHUNK")" "$REMOTE_CHUNK" >/dev/null 2>&1 || true
		got=$(run_adb shell "md5sum '$REMOTE_CHUNK' 2>/dev/null" | tr -d '\r' | awk '{print $1}')
		if [[ "$got" == "$want" ]]; then pushed=1; break; fi
		printf 'retry%d ' "$try"
		run_adb shell "rm -f '$REMOTE_CHUNK'" >/dev/null 2>&1 || true
		run_adb wait-for-device >/dev/null 2>&1 || true
	done
	if [[ "$pushed" != "1" ]]; then
		echo "FAILED"
		echo "Error: chunk $((i + 1)) would not transfer intact after $PUSH_RETRIES tries." >&2
		echo "  The USB link is dropping. Try a different cable or port." >&2
		exit 1
	fi

	run_adb shell "dd if='$REMOTE_CHUNK' of='$USERDATA_BLOCK' bs=1M seek=$off conv=fsync 2>/dev/null && rm -f '$REMOTE_CHUNK'"
	echo "ok"
done
run_adb shell "sync"

if [[ "$VERIFY" -eq 1 ]]; then
	# Full extent, not a prefix: a spot check passes while deeper blocks differ.
	echo "Verify: hashing $IMG_SIZE bytes back from $USERDATA_BLOCK (slow)..."
	DEV_MD5=$(run_adb shell "dd if=$USERDATA_BLOCK bs=1M count=$TOTAL_MIB 2>/dev/null | head -c $IMG_SIZE | md5sum" | tr -d '\r' | awk '{print $1}')
	HOST_MD5=$(head -c "$IMG_SIZE" "$FLASH_IMG" | md5sum | awk '{print $1}')
	if [[ "$DEV_MD5" == "$HOST_MD5" && -n "$DEV_MD5" ]]; then
		echo "Verify OK ($DEV_MD5)"
	else
		echo "Verify FAIL: device=$DEV_MD5 host=$HOST_MD5" >&2
		exit 1
	fi
fi

echo "Done. Reboot to postmarketOS rootfs on userdata."
