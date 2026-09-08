#!/bin/bash
# Reboot the device into a chosen mode and wait for it to arrive.
#
# Usage: ./enter-mode.sh twrp|bootloader|system [--dry-run]
#   twrp        recovery, where partitions are writable
#   bootloader  lk2nd's own fastboot
#   system      the installed postmarketOS
#
# lk2nd builds with USE_PON_REBOOT_REG=1 and reads the PMIC PON_SOFT_RB_SPARE
# register before it boots, so a running system selects the next mode by
# writing that register through the reboot syscall.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/transport.sh
source "$SCRIPT_DIR/lib/transport.sh"

DRY_RUN=0
MODE="${1:?Usage: $0 twrp|bootloader|system [--dry-run]}"
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

case "$MODE" in
	twrp)       ARG=recovery;   WANT=recovery ;;
	bootloader) ARG=bootloader; WANT=fastboot ;;
	system)     ARG="";         WANT=device ;;
	*) echo "Error: mode must be twrp, bootloader or system; got '$MODE'" >&2; exit 1 ;;
esac

if [[ "$DRY_RUN" -eq 1 ]]; then
	echo "Enter mode"
	echo "  target : $MODE"
	echo "  from   : (not detected)"
	echo "(dry run, nothing rebooted)"
	exit 0
fi

transport_detect
cat <<EOF
Enter mode
  target : $MODE
  from   : $TRANSPORT
EOF

case "$TRANSPORT" in
	twrp)
		if [[ -n "$ARG" ]]; then _adb reboot "$ARG"; else _adb reboot; fi ;;
	pmos)
		t_run "python3 -c \"import ctypes; ctypes.CDLL(None).syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, b'$ARG')\"" \
			>/dev/null 2>&1 || true ;;
	lk2nd-fastboot)
		[[ "$MODE" == system ]] || { echo "Error: lk2nd fastboot can only continue to system." >&2; exit 1; }
		_fb reboot >/dev/null ;;
esac

deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
	case "$WANT" in
		fastboot) _fb devices 2>/dev/null | grep -qi fastboot && { echo "  reached : $MODE"; exit 0; } ;;
		*) [[ "$(_adb_state)" == "$WANT" ]] && { echo "  reached : $MODE"; exit 0; } ;;
	esac
	sleep 2
done
echo "Error: device did not reach $MODE within 120s." >&2
exit 1
