#!/usr/bin/env python3
"""Minimal blurred lockscreen — password field with dots, Catppuccin monochrome"""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, GtkLayerShell, Gdk, GdkPixbuf, GLib

import ctypes
import ctypes.util
import os
import signal
import sys
import threading

# Block termination signals
for sig in (signal.SIGTERM, signal.SIGQUIT, signal.SIGHUP, signal.SIGINT):
    signal.signal(sig, signal.SIG_IGN)

# ── PAM authentication via ctypes ─────────────────────────────────

_libpam = ctypes.CDLL(ctypes.util.find_library("pam"))
_libc = ctypes.CDLL(ctypes.util.find_library("c"))

_libc.calloc.restype = ctypes.c_void_p
_libc.strdup.argtypes = [ctypes.c_char_p]
_libc.strdup.restype = ctypes.c_void_p

PAM_PROMPT_ECHO_OFF = 1
PAM_PROMPT_ECHO_ON = 2
PAM_SUCCESS = 0


class _PamMessage(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class _PamResponse(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_char_p), ("resp_retcode", ctypes.c_int)]


_CONV_FUNC = ctypes.CFUNCTYPE(
    ctypes.c_int, ctypes.c_int,
    ctypes.POINTER(ctypes.POINTER(_PamMessage)),
    ctypes.POINTER(ctypes.POINTER(_PamResponse)),
    ctypes.c_void_p
)


class _PamConv(ctypes.Structure):
    _fields_ = [("conv", _CONV_FUNC), ("appdata_ptr", ctypes.c_void_p)]


def pam_auth(username, password):
    pw = password.encode()

    @_CONV_FUNC
    def _conv(n, msg, resp, _data):
        arr_ptr = _libc.calloc(n, ctypes.sizeof(_PamResponse))
        arr = ctypes.cast(arr_ptr, ctypes.POINTER(_PamResponse))
        for i in range(n):
            if msg[i].contents.msg_style in (PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON):
                arr[i].resp = ctypes.cast(_libc.strdup(pw), ctypes.c_char_p)
                arr[i].resp_retcode = 0
        resp[0] = arr
        return 0

    # Keep reference so callback isn't garbage-collected
    conv = _PamConv(_conv, None)
    handle = ctypes.c_void_p()
    ret = _libpam.pam_start(b"swaylock", username.encode(),
                            ctypes.byref(conv), ctypes.byref(handle))
    if ret != PAM_SUCCESS:
        return False
    ret = _libpam.pam_authenticate(handle, 0)
    _libpam.pam_end(handle, ret)
    return ret == PAM_SUCCESS


# ── Theme colors ──────────────────────────────────────────────────

def get_colors():
    mode_file = os.path.expanduser("~/.config/theme-mode")
    try:
        mode = open(mode_file).read().strip()
    except Exception:
        mode = "dark"

    if mode == "dark":
        return dict(
            dim_overlay="rgba(0,0,0,0.3)",
            fg="#a6adc8", accent="#cdd6f4", dim="#6c7086",
            input_bg="#313244", input_border="#585b70",
            input_focus="#6c7086", error="#f38ba8",
        )
    else:
        return dict(
            dim_overlay="rgba(0,0,0,0.12)",
            fg="#6c6f85", accent="#4c4f69", dim="#9ca0b0",
            input_bg="#ccd0da", input_border="#acb0be",
            input_focus="#9ca0b0", error="#d20f39",
        )


# ── Lock window (one per monitor) ────────────────────────────────

class LockWindow(Gtk.Window):
    """Fullscreen blurred overlay — only primary gets the input field."""

    _scaled_cache = None

    def __init__(self, monitor, bg_pixbuf, colors, primary=False):
        super().__init__()
        self.bg_pixbuf = bg_pixbuf
        self.colors = colors
        self.primary = primary
        self.username = os.environ.get("USER", "user")

        # Prevent window from being closed without authentication
        self.connect("delete-event", lambda *a: True)

        # Layer-shell setup
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_namespace(self, "lockscreen")
        if monitor:
            GtkLayerShell.set_monitor(self, monitor)
        if primary:
            GtkLayerShell.set_keyboard_mode(
                self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)

        # Build UI
        overlay = Gtk.Overlay()
        self.drawing = Gtk.DrawingArea()
        self.drawing.connect("draw", self._draw_bg)
        overlay.add(self.drawing)

        if primary:
            c = colors
            css = Gtk.CssProvider()
            css.load_from_data(f"""
                .lock-label {{
                    color: {c['dim']};
                    font-family: 'Inter', sans-serif;
                    font-size: 22px;
                    font-weight: 300;
                    margin-bottom: 12px;
                }}
                .lock-entry {{
                    background: transparent;
                    border: none;
                    border-bottom: 1px solid {c['input_border']};
                    border-radius: 0;
                    color: {c['accent']};
                    font-family: 'Inter', sans-serif;
                    font-size: 14px;
                    padding: 6px 0px;
                    min-width: 220px;
                    box-shadow: none;
                    outline: none;
                }}
                .lock-entry:focus {{
                    border-bottom-color: {c['input_focus']};
                    box-shadow: none;
                }}
                .lock-error {{
                    color: {c['error']};
                    font-family: 'Inter', sans-serif;
                    font-size: 11px;
                    margin-top: 8px;
                }}
            """.encode())
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(), css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            vbox.set_halign(Gtk.Align.CENTER)
            vbox.set_valign(Gtk.Align.CENTER)

            label = Gtk.Label(label="Password")
            label.set_xalign(0)
            label.get_style_context().add_class("lock-label")
            vbox.pack_start(label, False, False, 0)

            self.entry = Gtk.Entry()
            self.entry.set_visibility(False)
            self.entry.set_invisible_char('\u25cf')  # ●
            self.entry.get_style_context().add_class("lock-entry")
            self.entry.connect("activate", self._on_submit)
            vbox.pack_start(self.entry, False, False, 0)

            self.error_label = Gtk.Label()
            self.error_label.get_style_context().add_class("lock-error")
            self.error_label.set_no_show_all(True)
            vbox.pack_start(self.error_label, False, False, 0)

            overlay.add_overlay(vbox)

        self.add(overlay)
        self.show_all()
        if primary:
            self.entry.grab_focus()

    def _draw_bg(self, widget, cr):
        alloc = widget.get_allocation()
        w, h = alloc.width, alloc.height
        if w < 2 or h < 2:
            return
        if (self._scaled_cache is None or
                self._scaled_cache.get_width() != w or
                self._scaled_cache.get_height() != h):
            self._scaled_cache = self.bg_pixbuf.scale_simple(
                w, h, GdkPixbuf.InterpType.BILINEAR)
        Gdk.cairo_set_source_pixbuf(cr, self._scaled_cache, 0, 0)
        cr.paint()
        # Dim overlay
        cr.set_source_rgba(0, 0, 0,
                           0.3 if "313244" in self.colors['input_bg'] else 0.12)
        cr.rectangle(0, 0, w, h)
        cr.fill()

    def _on_submit(self, entry):
        password = entry.get_text()
        if not password:
            return
        entry.set_sensitive(False)
        self.error_label.hide()
        threading.Thread(target=self._auth_thread,
                         args=(password,), daemon=True).start()

    def _auth_thread(self, password):
        ok = pam_auth(self.username, password)
        GLib.idle_add(self._auth_done, ok)

    def _auth_done(self, success):
        if success:
            Gtk.main_quit()
            return
        self.entry.set_text("")
        self.entry.set_sensitive(True)
        self.entry.grab_focus()
        self.error_label.set_text("Wrong password")
        self.error_label.show()
        GLib.timeout_add(2000, lambda: self.error_label.hide() or False)


# ── Main ──────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: lockscreen.py <blurred-image>", file=sys.stderr)
        sys.exit(1)

    image_path = sys.argv[1]
    bg = GdkPixbuf.Pixbuf.new_from_file(image_path)
    colors = get_colors()

    display = Gdk.Display.get_default()
    n = display.get_n_monitors()
    windows = []
    for i in range(n):
        mon = display.get_monitor(i)
        is_primary = (i == 0)  # first monitor gets input
        w = LockWindow(mon, bg, colors, primary=is_primary)
        windows.append(w)

    Gtk.main()


if __name__ == "__main__":
    main()
