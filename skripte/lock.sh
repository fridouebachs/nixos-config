#!/bin/bash
# lock.sh — Blurred screenshot lockscreen via swaylock

# Don't lock again if already locked
pgrep -x swaylock >/dev/null && exit 0

TMPIMG="/tmp/lockscreen-blur.png"

# Screenshot → resize down → smooth gaussian blur → resize back up
grim -t png - | magick - -resize 25% -blur 0x5 -resize 400% "$TMPIMG"

# Launch swaylock (daemonizes via config, uses ext-session-lock protocol)
exec swaylock -i "$TMPIMG"
