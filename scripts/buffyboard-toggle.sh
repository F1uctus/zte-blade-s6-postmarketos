#!/bin/sh
# Toggle the buffyboard on-screen keyboard, bound to the Home capacitive button.
# Native portrait only: buffyboard manages its own console layout.
if pkill -x buffyboard; then
	printf '\033[2J\033[H' > /dev/tty1 2>/dev/null		# repaint the console
else
	setsid buffyboard </dev/null >/dev/null 2>&1 &
fi
