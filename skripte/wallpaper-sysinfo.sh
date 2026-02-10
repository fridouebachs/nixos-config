#!/bin/bash
# wallpaper-sysinfo.sh — Dynamic wallpaper with monochrome system info panel
# Reads theme from ~/.config/theme-mode, updates every 5 seconds
# Handles SIGUSR1 for immediate regeneration (from theme-toggle.sh)

WALLPAPER="$HOME/.config/sway/wallpaper.png"
MODE_FILE="$HOME/.config/theme-mode"
CPU_PREV="/tmp/.wallpaper-cpu-prev"
FONT="JetBrains-Mono"

trap 'true' USR1

get_colors() {
    local mode
    mode=$(cat "$MODE_FILE" 2>/dev/null || echo "dark")
    if [ "$mode" = "dark" ]; then
        BG_TOP="#181825"; BG_BOT="#1e1e2e"
        PANEL_BG="rgba(17,17,27,0.55)"
        PANEL_BORDER="#313244"
        TEXT_COL="#a6adc8"; ACCENT="#bac2de"; DIM="#6c7086"
        BAR_BG="#313244"; BAR_FILL="#585b70"
    else
        BG_TOP="#e6e9ef"; BG_BOT="#eff1f5"
        PANEL_BG="rgba(220,224,232,0.55)"
        PANEL_BORDER="#bcc0cc"
        TEXT_COL="#6c6f85"; ACCENT="#5c5f77"; DIM="#9ca0b0"
        BAR_BG="#ccd0da"; BAR_FILL="#acb0be"
    fi
}

get_cpu_usage() {
    local user nice system idle iowait irq softirq _rest
    read _ user nice system idle iowait irq softirq _rest < /proc/stat
    local total=$((user + nice + system + idle + iowait + irq + softirq))
    local busy=$((user + nice + system + irq + softirq))

    if [ -f "$CPU_PREV" ]; then
        local prev_total prev_busy
        read prev_total prev_busy < "$CPU_PREV"
        local dt=$((total - prev_total))
        local db=$((busy - prev_busy))
        if [ "$dt" -gt 0 ]; then
            echo $((100 * db / dt))
        else
            echo 0
        fi
    else
        echo $((100 * busy / total))
    fi
    echo "$total $busy" > "$CPU_PREV"
}

generate_wallpaper() {
    get_colors

    # Screen resolution
    local W H
    W=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[0].current_mode.width // 1920' 2>/dev/null) || W=1920
    H=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[0].current_mode.height // 1080' 2>/dev/null) || H=1080

    # Collect stats
    local cpu_pct mem_pct disk_pct swap_pct
    cpu_pct=$(get_cpu_usage)
    mem_pct=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {if(t>0) printf "%.0f", (1-$2/t)*100}' /proc/meminfo)
    disk_pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
    swap_pct=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {if(t>0) printf "%.0f", (1-$2/t)*100; else print "0"}' /proc/meminfo)

    # Sanitize
    for var in cpu_pct mem_pct disk_pct swap_pct; do
        eval "[ -z \"\$$var\" ] && $var=0"
        eval "[ \"\$$var\" -gt 100 ] 2>/dev/null && $var=100"
    done

    # Collect info
    local hostname_str os_str kernel_str cpu_name uptime_str date_str
    hostname_str=$(hostname)
    os_str=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
    kernel_str=$(uname -r)
    cpu_name=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //;s/(R)//g;s/(TM)//g;s/  */ /g' | cut -c1-36)
    uptime_str=$(uptime -p | sed 's/up //')
    date_str=$(date '+%a, %e. %b %Y  %H:%M')

    local mem_total mem_used
    mem_total=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
    mem_used=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {printf "%.1f", (t-$2)/1024/1024}' /proc/meminfo)

    # Panel layout
    local panel_w=380 panel_h=310 margin=36 pad=20
    local panel_x=$((W - panel_w - margin))
    local panel_y=$((H - panel_h - margin))
    local cx=$((panel_x + pad))
    local cy=$((panel_y + pad))

    # Bar dimensions
    local bar_w=200 bar_h=8 bar_r=4
    local label_w=52
    local bar_x=$((cx + label_w))
    local row_h=26

    # Font sizes
    local fs=11 fl=15

    # Build command
    local cmd=(
        magick -size "${W}x${H}"
        "gradient:${BG_TOP}-${BG_BOT}"
    )

    # Panel background
    cmd+=(
        -fill "${PANEL_BG}"
        -stroke "${PANEL_BORDER}"
        -strokewidth 1
        -draw "roundrectangle ${panel_x},${panel_y} $((panel_x+panel_w)),$((panel_y+panel_h)) 14,14"
        -stroke none
    )

    # Hostname
    local y=$((cy + fl))
    cmd+=(
        -font "$FONT" -pointsize "$fl" -fill "${ACCENT}"
        -annotate "+${cx}+${y}" "$hostname_str"
    )

    # Separator
    y=$((y + 10))
    cmd+=(
        -fill "${PANEL_BORDER}"
        -draw "line ${cx},${y} $((panel_x + panel_w - pad)),${y}"
    )

    # Bars (monochrome)
    y=$((y + 18))
    local labels=("CPU" "MEM" "DISK" "SWAP")
    local pcts=("$cpu_pct" "$mem_pct" "$disk_pct" "$swap_pct")

    for i in 0 1 2 3; do
        local label="${labels[$i]}"
        local pct="${pcts[$i]}"
        local fill_w=$((bar_w * pct / 100))
        [ "$fill_w" -lt 1 ] && fill_w=1

        local bar_y=$((y + (row_h - bar_h) / 2))

        # Label
        cmd+=(
            -font "$FONT" -pointsize "$fs" -fill "${DIM}"
            -annotate "+${cx}+$((y + fs + 2))" "$label"
        )

        # Background bar
        cmd+=(
            -fill "${BAR_BG}"
            -draw "roundrectangle ${bar_x},${bar_y} $((bar_x+bar_w)),$((bar_y+bar_h)) ${bar_r},${bar_r}"
        )

        # Filled bar (monochrome)
        if [ "$fill_w" -gt "$((bar_r * 2))" ]; then
            cmd+=(
                -fill "${BAR_FILL}"
                -draw "roundrectangle ${bar_x},${bar_y} $((bar_x+fill_w)),$((bar_y+bar_h)) ${bar_r},${bar_r}"
            )
        fi

        # Percentage
        cmd+=(
            -font "$FONT" -pointsize "$fs" -fill "${TEXT_COL}"
            -annotate "+$((bar_x + bar_w + 8))+$((y + fs + 2))" "${pct}%"
        )

        y=$((y + row_h))
    done

    # Separator
    y=$((y + 4))
    cmd+=(
        -fill "${PANEL_BORDER}"
        -draw "line ${cx},${y} $((panel_x + panel_w - pad)),${y}"
    )

    # Info text
    y=$((y + 16))
    local info_lines=(
        "$os_str"
        "$kernel_str"
        "$cpu_name"
        "$uptime_str"
        "$date_str"
    )

    for line in "${info_lines[@]}"; do
        cmd+=(
            -font "$FONT" -pointsize "$fs" -fill "${DIM}"
            -annotate "+${cx}+${y}" "$line"
        )
        y=$((y + 18))
    done

    cmd+=("$WALLPAPER")
    "${cmd[@]}" 2>/dev/null
}

# Double-buffer: start new swaybg BEFORE killing old one → no black frame
set_wallpaper() {
    swaybg -o '*' -i "$WALLPAPER" -m fill &
    local new_pid=$!
    sleep 0.3
    # Kill all swaybg except the new one
    for pid in $(pgrep -x swaybg); do
        [ "$pid" != "$new_pid" ] && kill "$pid" 2>/dev/null
    done
}

# Generate initial wallpaper and display it
generate_wallpaper
set_wallpaper

# Main loop
while true; do
    sleep 5 &
    wait $! 2>/dev/null || true

    generate_wallpaper
    set_wallpaper
done
