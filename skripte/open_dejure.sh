#!/usr/bin/env bash
# open_dejure.sh - robust gegen leere swaymsg-Ausgaben
# Liest Markierung (primary/clipboard), erkennt §/Art (inkl. Buchstaben) und öffnet dejure.
# Wenn im aktuellen Workspace kein Brave-Fenster existiert: starte Brave mit --new-window im aktuellen WS.
# Log: /tmp/open_dejure_run.log

LOG=/tmp/open_dejure_run.log
echo "=== run $(date --iso-8601=seconds) ===" >>"$LOG"

log(){ echo "$*" | tee -a "$LOG"; }
notify(){ notify-send "open_dejure" "$1" || true; log "$1"; }

# 1) Auswahl holen: primary selection zuerst, fallback clipboard
sel="$(wl-paste --primary 2>/dev/null || true)"
if [ -z "$sel" ]; then
  sel="$(wl-paste 2>/dev/null || true)"
fi
sel="$(printf '%s' "$sel" | sed -n '1p' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
log "selection: '$sel'"

if [ -z "$sel" ]; then
  notify "Keine Markierung / kein Clipboard-Text gefunden."
  exit 2
fi

# 2) Erkennung §/Art inkl. Buchstaben
law_from_text="$(printf '%s' "$sel" | grep -oEi '\b(BGB|VVG|HGB|StGB|GG|ZPO|StPO|SGB[IVX]+|AO)\b' | head -n1 | tr '[:lower:]' '[:upper:]' || true)"
para="$(printf '%s' "$sel" | grep -oEi '§\s*[0-9]+[A-Za-z]?' | grep -oEi '[0-9]+[A-Za-z]?' || true)"
art="$(printf '%s' "$sel" | grep -oEi 'Art\.?\s*[0-9]+[A-Za-z]?' | grep -oEi '[0-9]+[A-Za-z]?' || true)"

log "detected: law_from_text='$law_from_text' para='$para' art='$art'"

if [ -n "$para" ]; then
  law="${law_from_text:-BGB}"
  num="$para"
elif [ -n "$art" ]; then
  law="${law_from_text:-GG}"
  num="$art"
else
  notify "Kein § oder Art. erkannt."
  exit 3
fi

law_norm="$(printf '%s' "$law" | tr '[:lower:]' '[:upper:]')"
url="https://dejure.org/gesetze/${law_norm}/${num}.html"
log "target URL: $url"

# 3) Ermittele aktuellen Workspace sicher (prüfe, ob swaymsg etwas zurückgibt)
ws_json="$(swaymsg -t get_workspaces 2>/dev/null || true)"
if [ -z "$ws_json" ]; then
  log "swaymsg get_workspaces lieferte nichts."
  current_ws=""
else
  current_ws="$(printf '%s' "$ws_json" | python3 - <<'PY' 2>/dev/null || true
import sys,json
try:
    a=json.load(sys.stdin)
    for w in a:
        if w.get("focused"):
            print(w.get("name") or "")
            sys.exit(0)
except Exception:
    pass
PY
)"
fi
log "current_ws='$current_ws'"

# 4) Prüfe, ob im aktuellen Workspace ein Browserfenster existiert.
has_browser="no"
if [ -n "$current_ws" ]; then
  tree_json="$(swaymsg -t get_tree 2>/dev/null || true)"
  if [ -z "$tree_json" ]; then
    log "swaymsg get_tree lieferte nichts."
    has_browser="no"
  else
    # nur parsen, wenn nicht leer
    has_browser="$(printf '%s' "$tree_json" | python3 - "$current_ws" <<'PY' 2>/dev/null || true
import sys,json,re
try:
    tree=json.load(sys.stdin)
    wsname=sys.argv[1]
    browser_re=re.compile(r'brave|brave-browser|firefox|chromium|chrome|google-chrome', re.I)
    def find(node):
        if node.get("type")=="workspace" and node.get("name")==wsname:
            stack=[node]
            while stack:
                n=stack.pop()
                wp=n.get("window_properties") or {}
                appid=n.get("app_id") or ""
                cls=wp.get("class") or ""
                name=n.get("name") or ""
                combined=" ".join([appid,cls,name])
                if browser_re.search(combined):
                    print("yes"); return
                for k in ("nodes","floating_nodes"):
                    for ch in n.get(k,[]):
                        stack.append(ch)
            print("no"); return
        for k in ("nodes","floating_nodes"):
            for ch in node.get(k,[]):
                find(ch)
    find(tree)
except Exception:
    pass
PY
)"
    # ensure a sane default
    has_browser="${has_browser:-no}"
  fi
fi
log "has_browser_in_ws='$has_browser'"

# 5) Pfad zu Brave herausfinden (robust)
BRAVE_PATH=""
if [ -x "/usr/bin/brave-browser" ]; then
  BRAVE_PATH="/usr/bin/brave-browser"
elif command -v brave >/dev/null 2>&1; then
  BRAVE_PATH="$(command -v brave)"
elif command -v brave-browser >/dev/null 2>&1; then
  BRAVE_PATH="$(command -v brave-browser)"
fi
log "brave_path='$BRAVE_PATH'"

# 6) Öffnen / Starten
if [ "$has_browser" = "yes" ] && [ -n "$BRAVE_PATH" ]; then
  log "öffne URL im vorhandenen Brave-Fenster (Brave wird den Tab an bestehendes Fenster senden)."
  "$BRAVE_PATH" "$url" >/dev/null 2>&1 & disown || log "direct brave open failed"
  notify "Öffne in vorhandenem Brave-Fenster: ${law_norm} ${num}"
  exit 0
fi

if [ -n "$BRAVE_PATH" ]; then
  log "Starte Brave neu mit --new-window (soll neues Fenster im aktuellen WS erzeugen): $BRAVE_PATH --new-window $url"
  "$BRAVE_PATH" --new-window "$url" >/dev/null 2>&1 & disown || log "brave --new-window failed"
  notify "Starte Brave (neues Fenster): ${law_norm} ${num}"
  exit 0
fi

# fallback
log "kein Brave gefunden, fallback xdg-open"
xdg-open "$url" >/dev/null 2>&1 || log "xdg-open failed"
notify "Öffne (Fallback): ${law_norm} ${num}"
exit 0
