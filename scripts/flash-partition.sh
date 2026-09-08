#!/bin/bash
# Write an image to a device partition in whichever mode the device is in.
#
# Usage: ./flash-partition.sh --target <label> [--offset-kb N] [--verify]
#                             [--dry-run] /path/to/image
#   --target      partition label: boot, system, userdata, misc, splash
#   --offset-kb   start this far into the partition (default 0)
#   --verify      hash the written extent back and compare
#   --dry-run     print what would happen and exit; needs no device
#
# Env: ADB_SERIAL  CHUNK_MIB=512  PUSH_RETRIES=4  TMPDIR=/var/tmp
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/transport.sh
source "$SCRIPT_DIR/lib/transport.sh"

TARGET=""; OFFSET_KB=0; VERIFY=0; DRY_RUN=0
while [[ "${1:-}" == --* ]]; do
	case "$1" in
		--target)    TARGET="$2"; shift ;;
		--offset-kb) OFFSET_KB="$2"; shift ;;
		--verify)    VERIFY=1 ;;
		--dry-run)   DRY_RUN=1 ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
	shift
done
[[ -n "$TARGET" ]] || { echo "Error: --target is required" >&2; exit 1; }
(( OFFSET_KB % 4 == 0 )) || { echo "Error: --offset-kb must be a multiple of 4" >&2; exit 1; }
IMG="${1:?Usage: $0 --target <label> [--offset-kb N] [--verify] [--dry-run] <image>}"
[[ -f "$IMG" ]] || { echo "Error: not a file: $IMG" >&2; exit 1; }
IMG="$(readlink -f "$IMG")"

for tool in dd md5sum od; do
	command -v "$tool" >/dev/null || { echo "Error: $tool is required" >&2; exit 1; }
done

CHUNK_MIB="${CHUNK_MIB:-512}"
PUSH_RETRIES="${PUSH_RETRIES:-4}"
IMG_SIZE=$(stat -c%s "$IMG")

# An Android sparse image expands to blk_sz * total_blks, at offsets 12 and 16.
IS_SPARSE=0
RAW_SIZE="$IMG_SIZE"
if file -b "$IMG" | grep -q 'Android sparse'; then
	IS_SPARSE=1
	_blk=$((0x$(od -An -tx4 -j12 -N4 "$IMG" | tr -d ' ')))
	_cnt=$((0x$(od -An -tx4 -j16 -N4 "$IMG" | tr -d ' ')))
	RAW_SIZE=$((_blk * _cnt))
fi

# The gzip probe is meaningful only for a boot image whose payload is a
# compressed kernel; lk2nd's payload is not one.
kernel_is_gzip() {
	python3 - "$1" <<'PY' 2>/dev/null
import sys, struct
d = open(sys.argv[1], 'rb').read(4096)
if d[:8] != b'ANDROID!':
    sys.exit(1)
page = struct.unpack_from('<8I', d, 8)[7]
sys.exit(0 if open(sys.argv[1], 'rb').read(page + 2)[page:page + 2] == b'\x1f\x8b' else 1)
PY
}
GZIP_CHECK=0
if command -v python3 >/dev/null && kernel_is_gzip "$IMG"; then GZIP_CHECK=1; fi

if [[ "$DRY_RUN" -eq 1 ]]; then
	NODE="(resolved on device)"; MODE="(not detected)"; PART_SIZE=0
else
	transport_detect
	MODE="$TRANSPORT"
	t_check_writable "$TARGET"
	NODE=$(t_resolve "$TARGET")
	PART_SIZE=$(t_run "blockdev --getsize64 $NODE" | tr -d '\r')
	[[ "$PART_SIZE" =~ ^[0-9]+$ ]] || { echo "Error: cannot read the size of $NODE" >&2; exit 1; }
	if (( RAW_SIZE + OFFSET_KB * 1024 > PART_SIZE )); then
		echo "Error: $((RAW_SIZE / 1048576)) MiB at +${OFFSET_KB}KiB overruns $NODE ($((PART_SIZE / 1048576)) MiB)" >&2
		exit 1
	fi
fi

checks=""
[[ "$VERIFY" -eq 1 ]] && checks+=" written-extent md5"
[[ "$GZIP_CHECK" -eq 1 ]] && checks+=" kernel-gzip"
(( OFFSET_KB > 0 )) && checks+=" head-intact"
cat <<EOF
Flash partition
  source : $IMG ($((RAW_SIZE / 1048576)) MiB$([[ "$IS_SPARSE" -eq 1 ]] && echo ", sparse"))
  target : $TARGET -> $NODE$([[ "$OFFSET_KB" -gt 0 ]] && echo " at ${OFFSET_KB} KiB")
  mode   : $MODE
  checks :${checks:- none}
EOF
[[ "$DRY_RUN" -eq 1 ]] && { echo "(dry run, nothing written)"; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/var/tmp}/zte-flash.XXXXXX")
STAGING=$(t_staging_dir)
cleanup() { rm -rf "$WORK"; t_run "rm -rf '$STAGING'" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if [[ "$IS_SPARSE" -eq 1 ]]; then
	command -v simg2img >/dev/null || { echo "Error: simg2img is required for a sparse image" >&2; exit 1; }
	simg2img "$IMG" "$WORK/raw.img"
	IMG="$WORK/raw.img"
	IMG_SIZE=$(stat -c%s "$IMG")
fi

t_prepare_staging
TOTAL_MIB=$(( (IMG_SIZE + 1048575) / 1048576 ))
CHUNKS=$(( (TOTAL_MIB + CHUNK_MIB - 1) / CHUNK_MIB ))
BLK=4096
SEEK_BLK=$(( OFFSET_KB * 1024 / BLK ))
BLK_PER_MIB=$(( 1048576 / BLK ))

# Everything before the offset belongs to someone else - lk2nd lives in the
# first 512 KiB of boot - so hash it and refuse to finish if the write moved it.
HEAD_BEFORE=""
if (( SEEK_BLK > 0 )); then
	HEAD_BEFORE=$(t_run "dd if=$NODE bs=$BLK count=$SEEK_BLK 2>/dev/null | md5sum" | tr -d '\r' | awk '{print $1}')
fi

for ((i = 0; i < CHUNKS; i++)); do
	off=$(( i * CHUNK_MIB ))
	dd if="$IMG" of="$WORK/chunk" bs=1M skip="$off" count="$CHUNK_MIB" status=none
	want=$(md5sum "$WORK/chunk" | awk '{print $1}')
	[[ "$CHUNKS" -gt 1 ]] && printf '  chunk %d/%d ... ' "$((i + 1))" "$CHUNKS"

	pushed=0
	for ((try = 1; try <= PUSH_RETRIES; try++)); do
		t_push "$WORK/chunk" "$STAGING/chunk" || true
		got=$(t_run "md5sum '$STAGING/chunk' 2>/dev/null" | tr -d '\r' | awk '{print $1}')
		[[ "$got" == "$want" ]] && { pushed=1; break; }
		t_run "rm -f '$STAGING/chunk'" >/dev/null 2>&1 || true
	done
	if [[ "$pushed" != 1 ]]; then
		echo "FAILED" >&2
		echo "Error: chunk $((i + 1)) did not transfer intact in $PUSH_RETRIES tries." >&2
		exit 1
	fi

	t_run "dd if='$STAGING/chunk' of='$NODE' bs=$BLK seek=$(( SEEK_BLK + off * BLK_PER_MIB )) conv=notrunc,fsync 2>/dev/null && rm -f '$STAGING/chunk'"
	[[ "$CHUNKS" -gt 1 ]] && echo ok
done
t_run "sync"

if [[ -n "$HEAD_BEFORE" ]]; then
	head_after=$(t_run "dd if=$NODE bs=$BLK count=$SEEK_BLK 2>/dev/null | md5sum" | tr -d '\r' | awk '{print $1}')
	if [[ "$head_after" != "$HEAD_BEFORE" ]]; then
		echo "  head-intact: FAILED - the first ${OFFSET_KB} KiB changed" >&2
		exit 1
	fi
	echo "  head-intact: ok (first ${OFFSET_KB} KiB unchanged)"
fi

# One read-back serves both checks when the image is small enough to pull.
if [[ "$GZIP_CHECK" -eq 1 ]]; then
	t_readback "dd if=$NODE bs=$BLK skip=$SEEK_BLK count=$(( TOTAL_MIB * BLK_PER_MIB )) 2>/dev/null" \
		| head -c "$IMG_SIZE" > "$WORK/readback"
	if [[ "$VERIFY" -eq 1 ]]; then
		if cmp -s "$WORK/readback" "$IMG"; then echo "  written-extent md5: ok"
		else echo "  written-extent md5: FAILED" >&2; exit 1; fi
	fi
	if python3 - "$WORK/readback" <<'PY'
import sys, struct, zlib
d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'ANDROID!', "bad boot header on device"
ksz, _, _, _, _, _, _, page = struct.unpack_from('<8I', d, 8)
blob = d[page:page + ksz]
i = blob.find(b'\xd0\x0d\xfe\xed')
blob = blob[:i] if i > 0 else blob
z = zlib.decompressobj(16 + zlib.MAX_WBITS)
n = sum(len(z.decompress(blob[o:o + 65536])) for o in range(0, len(blob), 65536)) + len(z.flush())
assert n > 20_000_000, f"kernel decompressed to only {n} bytes"
PY
	then echo "  kernel-gzip: ok"
	else echo "  kernel-gzip: FAILED" >&2; exit 1; fi
elif [[ "$VERIFY" -eq 1 ]]; then
	dev=$(t_run "dd if=$NODE bs=$BLK skip=$SEEK_BLK count=$(( TOTAL_MIB * BLK_PER_MIB )) 2>/dev/null | head -c $IMG_SIZE | md5sum" \
		| tr -d '\r' | awk '{print $1}')
	host=$(head -c "$IMG_SIZE" "$IMG" | md5sum | awk '{print $1}')
	if [[ -n "$dev" && "$dev" == "$host" ]]; then echo "  written-extent md5: ok"
	else echo "  written-extent md5: FAILED (device=$dev host=$host)" >&2; exit 1; fi
fi

echo "Done."
