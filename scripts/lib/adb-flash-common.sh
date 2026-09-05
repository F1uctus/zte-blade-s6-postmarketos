# Shared adb helpers for TWRP flashing scripts.
# Source from repo scripts: source "$(dirname "$0")/lib/adb-flash-common.sh"

ADB="${ADB:-adb}"
ADB_SERIAL="${ADB_SERIAL:-ec74ca69}"

run_adb() {
	if [[ -n "$ADB_SERIAL" ]]; then
		"$ADB" -s "$ADB_SERIAL" "$@"
	else
		"$ADB" "$@"
	fi
}

adb_push_path() {
	local host_path="$1"
	if [[ "$ADB" == *adb* ]] && command -v wslpath &>/dev/null; then
		local win_path
		win_path=$(wslpath -w "$host_path" 2>/dev/null) && echo "$win_path" && return
	fi
	echo "$host_path"
}

# Resolve boot/userdata block devices from by-name symlinks.
resolve_block_device() {
	local name="$1"
	local default="$2"
	local resolved
	resolved=$(run_adb shell "readlink -f /dev/block/by-name/$name 2>/dev/null" | tr -d '\r')
	if [[ -n "$resolved" && "$resolved" != *"No such file"* ]]; then
		echo "$resolved"
		return
	fi
	# TWRP often exposes platform symlinks only
	resolved=$(run_adb shell "readlink -f /dev/block/platform/*/by-name/$name 2>/dev/null" | tr -d '\r' | head -1)
	if [[ -n "$resolved" && "$resolved" != *"No such file"* ]]; then
		echo "$resolved"
		return
	fi
	echo "$default"
}

resolve_boot_block() {
	resolve_block_device boot "${BOOT_BLOCK:-/dev/block/mmcblk0p21}"
}

resolve_userdata_block() {
	resolve_block_device userdata "${USERDATA_BLOCK:-/dev/block/mmcblk0p30}"
}

check_adb_device() {
	if ! run_adb get-state >/dev/null 2>&1; then
		echo "Error: adb device not ready (serial=${ADB_SERIAL:-auto}). Device must be in TWRP with adb." >&2
		exit 1
	fi
}
