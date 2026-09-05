#!/bin/sh
# cwstm32 accel -> fbcon console auto-rotation.
# Polls the sensor-hub accelerometer and sets /sys/class/graphics/fbcon/rotate
# (0=normal, 1=90, 2=180, 3=270) from the gravity direction. Console-only: the
# device is headless, so nothing else consumes orientation.

ROT=/sys/class/graphics/fbcon/rotate
LOG=${CWSTM32_AUTOROTATE_LOG:-}		# set to a path to trace decisions

# fbcon and the IIO device may not be up yet at boot; wait for both
DEV=
for try in $(seq 30); do
	for d in /sys/bus/iio/devices/iio:device*; do
		[ "$(cat "$d/name" 2>/dev/null)" = "cwstm32" ] && DEV="$d" && break
	done
	[ -n "$DEV" ] && [ -w "$ROT" ] && break
	sleep 1
done
[ -n "$DEV" ] && [ -w "$ROT" ] || exit 0

abs() { [ "$1" -lt 0 ] && echo $(( -$1 )) || echo "$1"; }

FLAT=600	# |z| above this (and dominant) => lying flat, hold last orientation
MARGIN=300	# dominant in-plane axis must beat the other by this (raw ~1000/g)

cur=$(cat "$ROT" 2>/dev/null); : "${cur:=0}"

# The cwstm32 hub intermittently stops streaming (reads return a byte-identical
# value with zero jitter). Rebind the i2c driver to recover it, then re-find the
# IIO device (its number can change across a rebind).
I2C_ID=0-003a
# Rebind recovers a soft freeze; a hard hang (-ENXIO) won't re-probe (needs a
# power-cycle) -> returns non-zero so the caller can back off instead of thrash.
cwstm32_recover() {
	DEV=
	echo "$I2C_ID" > /sys/bus/i2c/drivers/cwstm32/unbind 2>/dev/null
	sleep 1
	echo "$I2C_ID" > /sys/bus/i2c/drivers/cwstm32/bind 2>/dev/null
	sleep 2
	for d in /sys/bus/iio/devices/iio:device*; do
		[ "$(cat "$d/name" 2>/dev/null)" = "cwstm32" ] && DEV="$d" && break
	done
	[ -n "$DEV" ]
}

STALL=16	# ×0.5 s with no fresh data (read -ENXIO or zero jitter) => wedged hub
still=0; prev=
while :; do
	x=$(cat "$DEV/in_accel_x_raw" 2>/dev/null)
	y=$(cat "$DEV/in_accel_y_raw" 2>/dev/null)
	z=$(cat "$DEV/in_accel_z_raw" 2>/dev/null)
	# no fresh sample: read failed (hub NAKs -ENXIO) or byte-identical (frozen)
	if [ -z "$x" ] || [ -z "$y" ] || [ -z "$z" ] || [ "$x $y $z" = "$prev" ]; then
		still=$((still + 1))
		if [ "$still" -ge "$STALL" ]; then
			[ -n "$LOG" ] && echo "$(date +%T) wedged -> recover" >> "$LOG"
			cwstm32_recover || sleep 30	# hard hang: back off (needs reboot)
			still=0; prev=
		fi
		sleep 0.5; continue
	fi
	still=0; prev="$x $y $z"

	ax=$(abs "$x"); ay=$(abs "$y"); az=$(abs "$z")

	new="$cur"
	if [ "$az" -gt "$FLAT" ] && [ "$az" -ge "$ax" ] && [ "$az" -ge "$ay" ]; then
		:	# flat: keep current
	elif [ "$ay" -gt "$ax" ] && [ $((ay - ax)) -gt "$MARGIN" ]; then
		[ "$y" -gt 0 ] && new=0 || new=2		# portrait axis (CAL)
	elif [ "$ax" -gt "$ay" ] && [ $((ax - ay)) -gt "$MARGIN" ]; then
		[ "$x" -gt 0 ] && new=1 || new=3		# landscape axis (CAL)
	fi

	[ -n "$LOG" ] && echo "$(date +%T) x=$x y=$y z=$z -> rotate=$new (cur=$cur)" >> "$LOG"
	if [ "$new" != "$cur" ]; then
		echo "$new" > "$ROT" 2>/dev/null && cur="$new"
	fi
	sleep 0.5
done
