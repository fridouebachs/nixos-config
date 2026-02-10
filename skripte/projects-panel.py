#!/usr/bin/env python3
"""
Projects panel – scrollable project list matching the sysinfo wallpaper panel.
Anchored bottom-right, positioned to the left of the sysinfo panel.
Left-click opens project in Zed, right-click renames the display name.
"""

import json
import os
import subprocess
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GLib, Pango, GtkLayerShell

CODE_DIR = os.path.expanduser("~/Code")
NAMES_FILE = os.path.expanduser("~/.config/project-names.json")
MODE_FILE = os.path.expanduser("~/.config/theme-mode")

# Match sysinfo panel exactly: pad=20, margin=36, border-radius=14
# sysinfo: panel_w=380, panel_h=310
SYSINFO_W = 380
MARGIN = 36
GAP = 12
PAD = 20  # same as sysinfo pad=20


def get_theme():
    try:
        mode = open(MODE_FILE).read().strip()
    except Exception:
        mode = "dark"
    if mode == "dark":
        return {
            "panel_bg": "rgba(17,17,27,0.55)",
            "panel_border": "#313244",
            "accent": "#bac2de",
            "text": "#a6adc8",
            "dim": "#6c7086",
            "hover": "rgba(49,50,68,0.6)",
        }
    else:
        return {
            "panel_bg": "rgba(220,224,232,0.55)",
            "panel_border": "#bcc0cc",
            "accent": "#5c5f77",
            "text": "#6c6f85",
            "dim": "#9ca0b0",
            "hover": "rgba(204,208,218,0.6)",
        }


def load_names():
    try:
        with open(NAMES_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_names(names):
    os.makedirs(os.path.dirname(NAMES_FILE), exist_ok=True)
    with open(NAMES_FILE, "w") as f:
        json.dump(names, f, indent=2, ensure_ascii=False)


def get_projects():
    if not os.path.isdir(CODE_DIR):
        return []
    return sorted(
        [d for d in os.listdir(CODE_DIR)
         if os.path.isdir(os.path.join(CODE_DIR, d)) and not d.startswith(".")],
        key=str.lower,
    )


def build_css(theme):
    # Matches sysinfo: pad=20, fs=11, fl=15, row_h=26, border-radius 14
    return f"""
    #pp-window {{
        background-color: {theme["panel_bg"]};
        border: 1px solid {theme["panel_border"]};
        border-radius: 14px;
    }}
    #pp-title {{
        font-family: "JetBrains Mono";
        font-size: 15px;
        color: {theme["accent"]};
    }}
    #pp-sep {{
        background-color: {theme["panel_border"]};
        min-height: 1px;
    }}
    #pp-list {{
        background: transparent;
    }}
    #pp-list row {{
        background: transparent;
        border-radius: 4px;
    }}
    #pp-list row:hover {{
        background-color: {theme["hover"]};
    }}
    .pp-item {{
        font-family: "JetBrains Mono";
        font-size: 11px;
        color: {theme["dim"]};
    }}
    .pp-item:hover {{
        color: {theme["text"]};
    }}
    #pp-scroll {{
        background: transparent;
    }}
    #pp-scroll undershoot.top,
    #pp-scroll undershoot.bottom,
    #pp-scroll overshoot.top,
    #pp-scroll overshoot.bottom {{
        background: transparent;
    }}
    scrollbar slider {{
        min-width: 3px;
        min-height: 20px;
        border-radius: 2px;
        background-color: {theme["dim"]};
    }}
    scrollbar trough {{
        background: transparent;
    }}
    #rename-entry {{
        font-family: "JetBrains Mono";
        font-size: 11px;
        color: {theme["accent"]};
        background-color: {theme["hover"]};
        border: 1px solid {theme["panel_border"]};
        border-radius: 6px;
        padding: 6px 10px;
    }}
    """.encode()


class ProjectsPanel(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.BOTTOM)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(
            self, GtkLayerShell.Edge.RIGHT,
            MARGIN + SYSINFO_W + GAP,
        )
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, MARGIN)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        GtkLayerShell.set_exclusive_zone(self, -1)

        self.set_app_paintable(True)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            self.set_visual(visual)

        self.display_names = load_names()
        self._build_ui()
        self._apply_theme()
        self._populate()

        GLib.timeout_add_seconds(3, self._refresh)
        self.show_all()

    def _build_ui(self):
        # Outer frame = the rounded panel
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        frame.set_name("pp-window")

        # Inner box with pad=20 on all sides (matching sysinfo)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        inner.set_margin_start(PAD)
        inner.set_margin_end(PAD)
        inner.set_margin_top(PAD)
        inner.set_margin_bottom(PAD)

        # Title — matches sysinfo hostname: pointsize 15, ACCENT color
        self.title_label = Gtk.Label(label="Projekte")
        self.title_label.set_name("pp-title")
        self.title_label.set_halign(Gtk.Align.START)
        inner.pack_start(self.title_label, False, False, 0)

        # Separator — sysinfo: 10px below title
        sep = Gtk.Separator()
        sep.set_name("pp-sep")
        sep.set_margin_top(10)
        sep.set_margin_bottom(10)
        inner.pack_start(sep, False, False, 0)

        # Scrollable project list
        scroll = Gtk.ScrolledWindow()
        scroll.set_name("pp-scroll")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(100)
        scroll.set_max_content_height(220)
        scroll.set_propagate_natural_height(True)

        self.listbox = Gtk.ListBox()
        self.listbox.set_name("pp-list")
        self.listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self.listbox.set_activate_on_single_click(True)
        self.listbox.set_hexpand(True)
        self.listbox.connect("row-activated", self._on_row_click)

        scroll.add(self.listbox)
        inner.pack_start(scroll, True, True, 0)

        frame.pack_start(inner, True, True, 0)
        self.add(frame)

    def _apply_theme(self):
        theme = get_theme()
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(build_css(theme))
        screen = self.get_screen()
        Gtk.StyleContext.add_provider_for_screen(
            screen, css_provider, 800
        )
        self._css_provider = css_provider
        self._current_theme_mode = self._read_mode()

    def _read_mode(self):
        try:
            return open(MODE_FILE).read().strip()
        except Exception:
            return "dark"

    def _populate(self):
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        self._projects = get_projects()
        for folder in self._projects:
            display = self.display_names.get(folder, folder)
            row = Gtk.ListBoxRow()
            row.folder_name = folder

            ebox = Gtk.EventBox()
            ebox.connect("button-press-event", self._on_button_press, row)

            # Match sysinfo info-text: pointsize 11, 18px line spacing
            # row_h=26 in sysinfo → use ~26px total row height
            label = Gtk.Label(label=display)
            label.set_halign(Gtk.Align.START)
            label.get_style_context().add_class("pp-item")
            # 26px row_h with ~15px font ≈ ~5-6px vertical padding
            label.set_margin_top(5)
            label.set_margin_bottom(5)

            ebox.add(label)
            row.add(ebox)
            self.listbox.add(row)

        self.listbox.show_all()

    def _on_button_press(self, widget, event, row):
        if event.button == 3:
            self._rename_dialog(row)
            return True
        return False

    def _on_row_click(self, listbox, row):
        path = os.path.join(CODE_DIR, row.folder_name)
        subprocess.Popen(["zed", path])

    def _rename_dialog(self, row):
        folder = row.folder_name
        current = self.display_names.get(folder, folder)

        dialog = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
        GtkLayerShell.init_for_window(dialog)
        GtkLayerShell.set_layer(dialog, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_keyboard_mode(dialog, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        GtkLayerShell.set_exclusive_zone(dialog, -1)

        dialog.set_app_paintable(True)
        screen = dialog.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            dialog.set_visual(visual)

        dialog.set_default_size(240, -1)
        dialog.set_name("pp-window")

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        vbox.set_margin_start(PAD)
        vbox.set_margin_end(PAD)
        vbox.set_margin_top(PAD)
        vbox.set_margin_bottom(PAD)

        entry = Gtk.Entry()
        entry.set_name("rename-entry")
        entry.set_text(current)
        vbox.pack_start(entry, False, False, 0)

        def on_confirm(_widget=None):
            new_name = entry.get_text().strip()
            if new_name and new_name != folder:
                self.display_names[folder] = new_name
            elif new_name == folder:
                self.display_names.pop(folder, None)
            save_names(self.display_names)
            self._populate()
            dialog.destroy()

        def on_key(_widget, event):
            if event.keyval == Gdk.KEY_Return:
                on_confirm()
                return True
            elif event.keyval == Gdk.KEY_Escape:
                dialog.destroy()
                return True
            return False

        entry.connect("activate", on_confirm)
        dialog.connect("key-press-event", on_key)

        dialog.add(vbox)
        dialog.show_all()

    def _refresh(self):
        if not self.get_visible() or not self.get_mapped():
            self.show_all()

        mode = self._read_mode()
        if mode != self._current_theme_mode:
            screen = self.get_screen()
            Gtk.StyleContext.remove_provider_for_screen(screen, self._css_provider)
            self._apply_theme()

        current = get_projects()
        if current != self._projects:
            self.display_names = load_names()
            self._populate()

        return True


if __name__ == "__main__":
    ProjectsPanel()
    Gtk.main()
