#!/bin/bash
lid_state=$(cat /proc/acpi/button/lid/LID/state | awk '{print $2}')
if [ "$lid_state" = "closed" ]; then
    # eDP-1 ausschalten, HDMI behalten
    swaymsg output eDP-1 disable
else
    swaymsg output eDP-1 enable
fi
