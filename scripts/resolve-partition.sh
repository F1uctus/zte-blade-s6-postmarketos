#!/bin/bash
# Print the device node for a partition label, as seen from TWRP over adb.
# Usage: ./resolve-partition.sh system|userdata|boot
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/adb-flash-common.sh
source "$SCRIPT_DIR/lib/adb-flash-common.sh"

NAME="${1:?Usage: $0 <partition-label>}"
check_adb_device

node=$(resolve_block_device "$NAME" "")
if [[ -z "$node" ]]; then
	echo "Error: could not resolve partition '$NAME' on the device" >&2
	exit 1
fi
echo "$node"
