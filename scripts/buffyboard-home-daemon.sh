#!/usr/bin/env python3
"""Watch the touch controller's capacitive Home key and toggle buffyboard.

The TD4291 reports Back/Home/Menu as KEY_BACK/KEY_HOMEPAGE/KEY_MENU on its
RMI4 input device; a Home press toggles the on-screen keyboard show/hide.
"""
import glob, os, struct, subprocess, time

KEY_HOMEPAGE = 172
EV_KEY = 1
EVENT_SIZE = 24                      # input_event on 64-bit
TOGGLE = "/usr/local/bin/buffyboard-toggle"


def find_device():
    for ev in sorted(glob.glob("/sys/class/input/event*")):
        try:
            name = open(os.path.join(ev, "device/name")).read().strip()
        except OSError:
            continue
        if "Synaptics" in name:
            return "/dev/input/" + os.path.basename(ev)
    return None


def main():
    dev = find_device()
    while not dev:
        time.sleep(2)
        dev = find_device()
    with open(dev, "rb", buffering=0) as f:
        while True:
            data = f.read(EVENT_SIZE)
            if not data or len(data) < EVENT_SIZE:
                continue
            _, _, etype, code, value = struct.unpack("qqHHi", data)
            if etype == EV_KEY and code == KEY_HOMEPAGE and value == 1:
                subprocess.Popen(["/bin/sh", TOGGLE])


if __name__ == "__main__":
    main()
