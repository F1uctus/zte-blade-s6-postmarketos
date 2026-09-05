#!/bin/bash
# Capture lk2nd/bootloader logs when the device is in fastboot mode.
# Usage: ./fastboot-log.sh [output-file]
# Use FASTBOOT=fastboot.exe when on WSL with Windows fastboot.
set -e
FASTBOOT="${FASTBOOT:-fastboot}"
OUT="${1:-fastboot-log-$(date +%Y%m%d-%H%M%S).bin}"

echo "Requesting log from device (fastboot oem log)..."
"$FASTBOOT" oem log || true
echo "Pulling staged log to $OUT..."
"$FASTBOOT" get_staged "$OUT" || { echo "Failed to get_staged. Try: $FASTBOOT get_staged $OUT"; exit 1; }
echo "Log saved to $OUT (binary). Inspect with strings or a text editor."
