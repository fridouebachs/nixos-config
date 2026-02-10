#!/bin/bash

# Zähle die Anzahl der sichtbaren Fenster im aktuellen Workspace
WINDOW_COUNT=$(swaymsg -t get_tree | jq '[.. | select(.type? == "con" and .visible? == true)] | length')

# Bestimme die nächste Split-Richtung basierend auf der Fensteranzahl
# Muster: 1->h, 2->v, 3->h, 4->v, 5->h, 6->v, ...
if [ $WINDOW_COUNT -eq 0 ] || [ $WINDOW_COUNT -eq 1 ]; then
    # Bei 0 oder 1 Fenster: horizontal split (neues Fenster rechts)
    swaymsg splith
elif [ $((WINDOW_COUNT % 2)) -eq 0 ]; then
    # Bei gerader Anzahl (2,4,6,...): vertical split
    swaymsg splitv
else
    # Bei ungerader Anzahl (3,5,7,...): horizontal split
    swaymsg splith
fi

# Führe das eigentliche Programm aus
exec "$@"
