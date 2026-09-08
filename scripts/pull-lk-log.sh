#!/bin/bash
# Pull lk2nd enhanced log from the last 64 KiB of the splash partition (LKLG).
# Device must be in TWRP (or rooted system) with adb. Uses WITH_DEBUG_LOG_BUF build.
# Usage:
#   ./scripts/pull-lk-log.sh              # pull from device, write to repo root
#   ./scripts/pull-lk-log.sh [output-dir]  # pull from device, write to dir
#   ./scripts/pull-lk-log.sh existing.bin # parse existing 64K splash-tail dump only
# WSL: ADB=adb.exe ./scripts/pull-lk-log.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/transport.sh
source "$SCRIPT_DIR/lib/transport.sh"
ADB="${ADB:-adb}"
if [ -f "$1" ] && [ "${1%.bin}" != "$1" ]; then
  BIN="$1"
  OUT_DIR="$(dirname "$1")"
  SKIP_PULL=1
else
  OUT_DIR="${1:-$REPO_ROOT}"
  BIN="$OUT_DIR/lklog-splash-tail.bin"
  SKIP_PULL=0
fi
TXT="${BIN%.bin}.txt"

# Splash partition by name (standard on Qualcomm)
SPLASH_DEV="/dev/block/by-name/splash"
WRITE_LEN=65536

if [ "$SKIP_PULL" -eq 0 ]; then
  transport_detect
  SPLASH_DEV=$(t_run "readlink -f /dev/block/by-name/splash 2>/dev/null; \
    readlink -f /dev/block/platform/*/by-name/splash 2>/dev/null" | tr -d '\r' | head -1)
  if [ -z "$SPLASH_DEV" ]; then
    echo "Splash partition not found. Is device in TWRP/root?"
    exit 1
  fi
  echo "Using splash device: $SPLASH_DEV (serial ${ADB_SERIAL:-auto})"

  echo "Reading last ${WRITE_LEN} bytes of splash partition..."
  t_readback "size=\$(blockdev --getsize64 $SPLASH_DEV 2>/dev/null); \
    [ -n \"\$size\" ] && skip=\$(( (size / $WRITE_LEN) - 1 )) && dd if=$SPLASH_DEV bs=$WRITE_LEN skip=\$skip count=1 2>/dev/null" > "$BIN" || true

  # Fallback: read last block of a fixed 1MiB tail (splash is usually >= 1MiB)
  if [ ! -s "$BIN" ]; then
    echo "blockdev failed, trying fixed skip (1MiB tail)..."
    t_readback "dd if=$SPLASH_DEV bs=$WRITE_LEN skip=15 count=1 2>/dev/null" > "$BIN" || true
  fi

  if [ ! -s "$BIN" ]; then
    echo "Failed to read splash tail. Try in TWRP: adb shell, then:"
    echo "  blockdev --getsize64 $SPLASH_DEV"
    echo "  dd if=$SPLASH_DEV bs=65536 skip=\$(( (\$size/65536)-1 )) count=1 of=/tmp/lklog.bin"
    echo "  exit; adb pull /tmp/lklog.bin ."
    echo "Then: $0 $BIN"
    exit 1
  fi
else
  echo "Parsing existing dump: $BIN"
fi

echo "Parsing LKLG and printing log to $TXT..."
python3 - "$BIN" "$TXT" << 'PY'
import sys, struct

LKLG_MAGIC = 0x474c4b4c  # 'LKLG' LE
def stage_str(v):
    if v == 0: return "(none)"
    # Stage is stored LE; C comment is high-byte first (e.g. 0x54494E49 = 'TINI')
    return "".join(chr((v >> (8 * (3 - i))) & 0xff) for i in range(4))

path = sys.argv[1]
out_path = sys.argv[2]
with open(path, "rb") as f:
    data = f.read()

if len(data) < 28:
    with open(out_path, "w") as out:
        out.write("Too small for LKLG header (%d bytes)\n" % len(data))
    sys.exit(0)

magic, version, length, seq, time_ms, stage, reserved = struct.unpack_from("<7I", data)
if magic != LKLG_MAGIC:
    with open(out_path, "w") as out:
        out.write("Bad magic: 0x%08x (expected LKLG 0x%08x)\n" % (magic, LKLG_MAGIC))
        out.write("First 64 bytes hex: %s\n" % data[:64].hex())
    sys.exit(0)

log_data = data[28:28+length] if length else b""
# Log buffer is circular; treat as text, drop nulls for display
text = log_data.decode("utf-8", errors="replace").replace("\x00", "")

with open(out_path, "w") as out:
    out.write("stage=%s (0x%08x) seq=%u time_ms=%u length=%u\n" % (stage_str(stage), stage, seq, time_ms, length))
    out.write("---\n")
    out.write(text)
    if text and not text.endswith("\n"):
        out.write("\n")

print("stage=%s seq=%u time_ms=%u length=%u" % (stage_str(stage), seq, time_ms, length))
PY

echo "Log saved to $TXT"
cat "$TXT"
