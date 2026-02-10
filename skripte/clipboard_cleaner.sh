#!/usr/bin/env bash
# clipboard_cleaner.sh - korrigierte Version
# Usage: clipboard_cleaner.sh start|stop|toggle|once|status
#
# Requirements: wl-clipboard (wl-paste, wl-copy), python3, notify-send (optional)

STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/clipboard-cleaner"
PIDFILE="$STATE_DIR/clipboard-cleaner.pid"
LOGFILE="$STATE_DIR/clipboard-cleaner.log"
PYTHON_SCRIPT="$STATE_DIR/cleaner.py"

mkdir -p "$STATE_DIR"

# write python helper (overwrites if changed)
cat > "$PYTHON_SCRIPT" <<'PY'
#!/usr/bin/env python3
import sys, re

def to_roman(n):
    n = int(n)
    vals = [(10,'X'),(9,'IX'),(5,'V'),(4,'IV'),(1,'I')]
    res = ''
    for v, s in vals:
        while n >= v:
            res += s
            n -= v
    return res

def clean_text(txt):

   # remove ANSI / terminal escape sequences
    txt = re.sub(r'\x1B\[[0-?]*[ -/]*[@-~]', '', txt)

    # remove soft hyphen at line breaks (rejoin the word)
    txt = re.sub(r'\u00ad[ \t]*[\r\n]+[ \t]*', '', txt)

    # remove remaining soft hyphens (not at line breaks)
    txt = txt.replace('\u00ad', '')

    # remove simple HTML tags
    txt = re.sub(r'<[^>]+>', '', txt)

    # REMOVE syllable hyphenation at line breaks
    txt = re.sub(r'(?<=\w)-[ \t]*[\r\n]+[ \t]*(?=\w)', '', txt)

    # join remaining lines
    txt = re.sub(r'[\r\n]+', ' ', txt)
    txt = re.sub(r'\s+', ' ', txt).strip()

    
    # NEUE REGEL: Ersetze $ durch § (mit Leerzeichen nach §)
    txt = re.sub(r'\$\s*', '§ ', txt)
    
    # Stelle sicher, dass nach jedem § ein Leerzeichen kommt (falls nicht schon vorhanden)
    txt = re.sub(r'§(?!\s)', '§ ', txt)
    
    # pattern: § (optional Abs. ) (optional S. )
    pattern = re.compile(
        r'§\s*(?P<par>\d+)'
        r'(?:\s*(?:,?\s*)(?:Abs\.?|Absatz)\s*(?P<abs>\d+))?'
        r'(?:\s*(?:,?\s*)(?:S\.?|Satz)\s*(?P<satz>\d+))?',
        flags=re.IGNORECASE)
    
    def repl(m):
        par = m.group('par')
        absn = m.group('abs')
        satz = m.group('satz')
        out = "§ " + par
        if absn:
            out += " " + to_roman(absn)
        if satz:
            out += " " + satz
        return out
    
    txt = pattern.sub(repl, txt)
    
    # If § exists, convert standalone Abs. X S. Y occurrences following it
    if "§" in txt:
        pattern2 = re.compile(
            r'(?:Abs\.?|Absatz)\s*(?P<abs>\d+)(?:\s*(?:,?\s*)(?:S\.?|Satz)\s*(?P<satz>\d+))?',
            flags=re.IGNORECASE)
        
        def repl2(m):
            absn = m.group("abs")
            satz = m.group("satz")
            out = to_roman(absn)
            if satz:
                out += " " + satz
            return out
        
        txt = pattern2.sub(repl2, txt)
    
    # Final whitespace cleanup
    txt = re.sub(r'\s+', ' ', txt).strip()
    
    # Remove spaces between consecutive § symbols 
    txt = re.sub(r'§\s+(?=§)', '§', txt)

    return txt

if __name__ == "__main__":
    data = sys.stdin.read()
    sys.stdout.write(clean_text(data))
PY

chmod +x "$PYTHON_SCRIPT" || true

is_running() {
    [[ -f "$PIDFILE" ]] || return 1
    pid=$(cat "$PIDFILE")
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

start_daemon() {
    if is_running; then
        echo "Already running (pid $(cat "$PIDFILE"))."
        return 0
    fi
    
    nohup bash -c "
        prev=''
        while true; do
            clip=\"\$(wl-paste 2>/dev/null || true)\"
            if [[ -z \"\$clip\" ]]; then
                sleep 0.5
                continue
            fi
            if [[ \"\$clip\" != \"\$prev\" ]]; then
                new=\"\$(printf \"%s\" \"\$clip\" | python3 \"$PYTHON_SCRIPT\")\"
                if [[ -n \"\$new\" && \"\$new\" != \"\$clip\" ]]; then
                    printf \"%s\" \"\$new\" | wl-copy
                    echo \"\$(date --iso-8601=seconds) cleaned clipboard\" >> \"$LOGFILE\"
                fi
                prev=\"\$clip\"
            fi
            sleep 0.4
        done
    " >"$LOGFILE" 2>&1 &
    
    echo $! >"$PIDFILE"
    echo "Started clipboard-cleaner (pid $(cat "$PIDFILE"))"
    notify-send "Clipboard Cleaner" "Bereinigungsmodus: AN" >/dev/null 2>&1 || true
}

stop_daemon() {
    if ! is_running; then
        echo "Not running."
        return 0
    fi
    
    pid=$(cat "$PIDFILE")
    kill "$pid" 2>/dev/null || true
    sleep 0.2
    if is_running; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
    echo "Stopped clipboard-cleaner."
    notify-send "Clipboard Cleaner" "Bereinigungsmodus: AUS" >/dev/null 2>&1 || true
}

toggle() {
    if is_running; then
        stop_daemon
    else
        start_daemon
    fi
}

status() {
    if is_running; then
        echo "Running (pid $(cat "$PIDFILE"))."
    else
        echo "Stopped."
    fi
}

once() {
    clip="$(wl-paste 2>/dev/null || true)"
    if [[ -z "$clip" ]]; then
        echo "No clipboard text available."
        exit 1
    fi
    
    new="$(printf "%s" "$clip" | python3 "$PYTHON_SCRIPT")"
    if [[ -n "$new" ]]; then
        printf "%s" "$new" | wl-copy
        notify-send "Clipboard Cleaner" "Clipboard einmalig bereinigt." >/dev/null 2>&1 || true
        echo "Done."
    else
        echo "Nothing changed."
    fi
}

case "${1:-status}" in
    start)  start_daemon ;;
    stop)   stop_daemon ;;
    toggle) toggle ;;
    once)   once ;;
    status) status ;;
    *)      echo "Usage: $0 start|stop|toggle|once|status" ; exit 2 ;;
esac
