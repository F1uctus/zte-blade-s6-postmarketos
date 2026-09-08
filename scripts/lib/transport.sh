# Device transport: detect the mode once, then talk to the device through the
# functions below. Source from repo scripts:
#   source "$(dirname "$0")/lib/transport.sh"
#
# Modes and what each may write:
#   twrp            recovery over adb   boot, misc, splash, system, userdata
#   pmos            running system over ssh   boot, misc, splash, the rootfs it
#                                             did not boot from
#   lk2nd-fastboot  lk2nd's own fastboot      nothing; RAM-boot only
#
# An operation a mode cannot serve is an error naming the mode. Nothing here
# falls back to another mode or to a guessed partition node.

ADB="${ADB:-adb}"
ADB_SERIAL="${ADB_SERIAL:-ec74ca69}"
FASTBOOT="${FASTBOOT:-fastboot}"
PMOS_HOST="${PMOS_HOST:-172.16.42.1}"
PMOS_USER="${PMOS_USER:-user}"
SSH_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

TRANSPORT=""

_adb() {
	if [[ -n "$ADB_SERIAL" ]]; then "$ADB" -s "$ADB_SERIAL" "$@"; else "$ADB" "$@"; fi
}

_adb_state() { _adb get-state 2>/dev/null | tr -d '\r'; }

FASTBOOT_SERIAL="${FASTBOOT_SERIAL:-$ADB_SERIAL}"
_fb() {
	if [[ -n "$FASTBOOT_SERIAL" ]]; then "$FASTBOOT" -s "$FASTBOOT_SERIAL" "$@"; else "$FASTBOOT" "$@"; fi
}

_ssh() { ssh "${SSH_OPTS[@]}" "$PMOS_USER@$PMOS_HOST" "$@"; }

# Run a command as root on a running system. The command travels base64-encoded
# so quoting cannot break it, which leaves stdin free for the sudo password.
_pmos_root() {
	local enc inner
	enc=$(printf '%s' "$1" | base64 | tr -d '\n')
	inner="echo $enc | base64 -d | sh"
	if [[ -n "${PMOS_SUDO_PASSWORD:-}" ]]; then
		printf '%s\n' "$PMOS_SUDO_PASSWORD" | _ssh "sudo -S -p '' sh -c \"$inner\""
	else
		_ssh "sudo -n sh -c \"$inner\""
	fi
}

# WSL: adb.exe needs a Windows path for push.
_push_path() {
	if [[ "$ADB" == *adb* ]] && command -v wslpath &>/dev/null; then
		local w; w=$(wslpath -w "$1" 2>/dev/null) && { echo "$w"; return; }
	fi
	echo "$1"
}

transport_detect() {
	case "$(_adb_state)" in
		recovery) TRANSPORT=twrp; return 0 ;;
		device)   TRANSPORT=twrp; return 0 ;;
	esac
	if _ssh true >/dev/null 2>&1; then
		TRANSPORT=pmos
		if ! _pmos_root true >/dev/null 2>&1; then
			echo "Error: $PMOS_USER@$PMOS_HOST answers but root is not reachable." >&2
			echo "  Set PMOS_SUDO_PASSWORD, or give the account passwordless sudo." >&2
			return 1
		fi
		return 0
	fi
	if _fb devices 2>/dev/null | grep -qi fastboot; then
		TRANSPORT=lk2nd-fastboot; return 0
	fi
	echo "Error: no device found (adb serial ${ADB_SERIAL:-auto}, ssh $PMOS_HOST, fastboot)." >&2
	return 1
}

# Run a shell command on the device; stdout is the command's stdout.
t_run() {
	case "$TRANSPORT" in
		twrp) _adb shell "$1" ;;
		pmos) _pmos_root "$1" ;;
		*) echo "Error: $TRANSPORT cannot run commands." >&2; return 1 ;;
	esac
}

# Copy a host file to the device.
t_push() {
	case "$TRANSPORT" in
		twrp) _adb push "$(_push_path "$1")" "$2" >/dev/null 2>&1 ;;
		pmos) scp "${SSH_OPTS[@]}" -q "$1" "$PMOS_USER@$PMOS_HOST:$2" ;;
		*) echo "Error: $TRANSPORT cannot copy files." >&2; return 1 ;;
	esac
}

# Read binary from the device to stdout. adb shell allocates a PTY that turns
# every 0x0a into 0x0d 0x0a, so this must never route through it.
t_readback() {
	case "$TRANSPORT" in
		twrp) _adb exec-out "$1" ;;
		pmos) _pmos_root "$1" ;;
		*) echo "Error: $TRANSPORT cannot read partitions." >&2; return 1 ;;
	esac
}

# Block device node for a partition label. Unresolvable is an error.
t_resolve() {
	local label="$1" node
	node=$(t_run "for p in /dev/block/by-name/$label \
	                       /dev/block/platform/*/by-name/$label \
	                       /dev/disk/by-partlabel/$label; do
	                  [ -b \"\$p\" ] && readlink -f \"\$p\" && break
	              done" | tr -d '\r' | head -1)
	if [[ -z "$node" ]] || ! t_run "[ -b \"$node\" ]"; then
		echo "Error: '$label' is not a block device in mode $TRANSPORT." >&2
		echo "  Recovery exposes /dev/block/...; a running system exposes /dev/... ." >&2
		return 1
	fi
	echo "$node"
}

# The partition the running system booted from. Its rootfs sits in a nested
# GPT inside that partition, reached through a loop device, so the mount source
# is a loop node and has to be traced back to its backing store.
_pmos_root_partition() {
	t_run 'root=$(findmnt -no SOURCE /)
	       case "$root" in
	         /dev/loop*)
	           base=$(lsblk -no PKNAME "$root" 2>/dev/null)
	           [ -n "$base" ] || base=${root#/dev/}
	           back=$(cat "/sys/class/block/$base/loop/backing_file" 2>/dev/null)
	           [ -n "$back" ] && root=$back ;;
	       esac
	       echo "$root"' | tr -d '\r' | head -1
}

# Refuse writes the mode cannot make safely.
t_check_writable() {
	local label="$1"
	case "$TRANSPORT" in
		twrp) return 0 ;;
		pmos)
			local node root
			node=$(t_resolve "$label") || return 1
			root=$(_pmos_root_partition)
			if [[ -n "$root" && "$root" == "$node" ]]; then
				echo "Error: '$label' ($node) holds the running rootfs; write it from twrp." >&2
				return 1
			fi
			return 0 ;;
		lk2nd-fastboot)
			echo "Error: lk2nd fastboot cannot write partitions on this device; it RAM-boots only." >&2
			return 1 ;;
	esac
}

# Somewhere on the device with room for one chunk. TWRP's /tmp is a small
# tmpfs, so recovery stages on the internal card instead.
t_staging_dir() {
	case "$TRANSPORT" in
		twrp) echo "/internal_sd/pmos-flash" ;;
		pmos) echo "/var/tmp/pmos-flash" ;;
		*) echo "Error: $TRANSPORT has no staging area." >&2; return 1 ;;
	esac
}

# Create it. Commands run as root but files arrive as the login user, so on a
# running system the directory has to belong to that user.
t_prepare_staging() {
	local dir; dir=$(t_staging_dir) || return 1
	case "$TRANSPORT" in
		twrp) t_run "mkdir -p '$dir'" >/dev/null ;;
		pmos) t_run "mkdir -p '$dir' && chown $PMOS_USER '$dir'" >/dev/null ;;
	esac
}
