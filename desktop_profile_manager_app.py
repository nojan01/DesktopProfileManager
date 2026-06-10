#!/usr/bin/env python3
"""
Desktop Profile Manager – macOS Menüleisten-App
Speichert und stellt Desktop-Icon-Positionen automatisch wieder her.

Copyright (c) 2026 Norbert Jander
Erstellt nach einer Idee von Norbert Jander mit Hilfe eines KI-Agents.
Lizenz: MIT (siehe LICENSE)
"""

import subprocess
import json
import stat
import shutil
import threading
import os
import time
import sys
from datetime import datetime
from pathlib import Path

import objc
import rumps
from AppKit import (
    NSApplication, NSApplicationActivationPolicyAccessory,
    NSWorkspace, NSWorkspaceDidWakeNotification,
    NSWindow, NSView, NSButton, NSScrollView, NSTextField,
    NSBackingStoreBuffered, NSWindowStyleMaskTitled,
    NSWindowStyleMaskClosable, NSWindowStyleMaskResizable,
    NSButtonTypeSwitch, NSBezelStyleRounded,
    NSFont, NSApp,
    NSApplicationActivationPolicyRegular,
    NSScreen,
    NSOpenPanel, NSSavePanel,
    NSEvent, NSEventMaskKeyDown,
    NSEventModifierFlagCommand, NSEventModifierFlagControl,
    NSEventModifierFlagOption, NSEventModifierFlagShift,
    NSColor, NSForegroundColorAttributeName,
    NSAlert, NSPopUpButton, NSAlertFirstButtonReturn,
)
from Foundation import (
    NSObject, NSMakeRect, NSBundle as FoundationNSBundle,
    NSMutableAttributedString, NSMakeRange,
)

# Konstanten die in manchen PyObjC-Versionen fehlen
NSControlStateValueOn = 1
NSControlStateValueOff = 0

# CGSessionCopyCurrentDictionary laden (ohne pyobjc-framework-Quartz)
_cg_functions = {}
objc.loadBundleFunctions(
    FoundationNSBundle.bundleWithPath_('/System/Library/Frameworks/ApplicationServices.framework'),
    _cg_functions,
    [('CGSessionCopyCurrentDictionary', b'@',)]
)
_CGSessionCopyCurrentDictionary = _cg_functions['CGSessionCopyCurrentDictionary']

# Dock-Icon unterdrücken
NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyAccessory)

# ─── Konfiguration ─────────────────────────────────────────────────
APP_NAME = "Desktop Profile Manager"
APP_ICON = None  # Wird unten gesetzt falls vorhanden

# Aktuelle App-Version (für die Update-Prüfung gegen GitHub-Releases).
APP_VERSION = "1.2.0"
# GitHub-Repository, dessen neuestes Release auf Updates geprüft wird.
GITHUB_REPO = "nojan01/IconGuard"
GITHUB_RELEASES_API = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
GITHUB_RELEASES_URL = f"https://github.com/{GITHUB_REPO}/releases"

PROFILES_DIR = Path.home() / ".iconguard"
CONFIG_PATH = PROFILES_DIR / "_config.json"

DEFAULT_CONFIG = {
    "auto_restore_enabled": False,
    "auto_restore_profile": "default",
    "auto_restore_interval_minutes": 30,
    "restore_on_login": True,
    "restore_on_wake": True,
    "restore_wallpaper": True,
    "restore_apps": True,
    "hide_other_apps": False,
    "quit_other_apps": False,
    "app_exclusions": [],
    "language": "system",      # "system" | "de" | "en"
    "app_launch_delay": 1.5,   # Verzögerung zwischen App-Starts (Sekunden)
    "hotkeys_enabled": False,  # Globale Kurzbefehle für die ersten Profile
    "hotkey_modifier": "cmd_ctrl",  # Modifier: cmd_ctrl | ctrl | opt_cmd | ctrl_shift
    "auto_switch_enabled": False,  # Zeit-/WLAN-basiertes Umschalten
    "auto_switch_rules": [],   # Liste: {type:"time"|"wifi", value, profile}
    "migrated_iconguard": False,  # Einmalige Migration des alten IconGuard-Autostarts
}

INTERVAL_OPTIONS = [5, 10, 15, 30, 60, 120, 240]

# Verfügbare Modifier-Kombinationen für die globalen Kurzbefehle.
# Jeder Eintrag: key -> (Anzeige-Symbol, Liste der NSEventModifierFlags)
HOTKEY_MODIFIERS = {
    "cmd_ctrl": "⌘⌃",
    "ctrl": "⌃",
    "opt_cmd": "⌥⌘",
    "ctrl_shift": "⌃⇧",
}


# ─── Sprache / Lokalisierung ──────────────────────────────────────

# Aktuelle Sprache ("de" oder "en"); wird beim Start aus der Konfiguration
# aufgelöst. Module-weite Variable, damit auch die Hilfsfunktionen und die
# NSObject-Delegates über ``L()`` übersetzen können.
CURRENT_LANG = "de"


def detect_system_language() -> str:
    """Ermittelt die Systemsprache: "de" nur bei deutschem System, sonst "en"."""
    try:
        from Foundation import NSLocale
        langs = NSLocale.preferredLanguages()
        if langs and str(langs[0]).lower().startswith("de"):
            return "de"
    except Exception:
        pass
    return "en"


def resolve_language(config: dict) -> str:
    """Setzt ``CURRENT_LANG`` anhand der Konfiguration und gibt sie zurück."""
    global CURRENT_LANG
    pref = (config or {}).get("language", "system")
    if pref == "en":
        CURRENT_LANG = "en"
    elif pref == "de":
        CURRENT_LANG = "de"
    else:
        CURRENT_LANG = detect_system_language()
    return CURRENT_LANG


def L(de: str, en: str) -> str:
    """Gibt je nach aktueller Sprache den deutschen oder englischen Text zurück."""
    return en if CURRENT_LANG == "en" else de


# ─── AppleScript / Finder Funktionen ──────────────────────────────

def run_applescript(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def get_icon_positions() -> dict:
    script = '''
    tell application "Finder"
        set output to ""
        set allItems to every item of desktop
        repeat with anItem in allItems
            set itemName to name of anItem as text
            set itemPos to desktop position of anItem
            set x to item 1 of itemPos
            set y to item 2 of itemPos
            set output to output & itemName & "||" & x & "||" & y & linefeed
        end repeat
        return output
    end tell
    '''
    raw = run_applescript(script)
    positions = {}
    for line in raw.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        parts = line.split("||")
        if len(parts) == 3:
            name = parts[0]
            try:
                x = int(float(parts[1]))
                y = int(float(parts[2]))
                positions[name] = {"x": x, "y": y}
            except ValueError:
                pass
    return positions


def set_icon_positions(positions: dict) -> tuple:
    """Setzt Positionen per Referenz-Iteration (umgeht macOS 26 Namen-Lookup-Bug)."""
    if not positions:
        return 0, 0
    # Baue AppleScript-Liste {name, x, y}
    entries = []
    for name, pos in positions.items():
        escaped = name.replace('\\', '\\\\').replace('"', '\\"')
        entries.append(f'{{"{escaped}", {pos["x"]}, {pos["y"]}}}')
    targets_literal = "{" + ", ".join(entries) + "}"
    script = f'''
    set targets to {targets_literal}
    set successCount to 0
    set failedCount to 0
    tell application "Finder"
        set allItems to every item of desktop
        repeat with t in targets
            set tName to item 1 of t
            set tX to item 2 of t
            set tY to item 3 of t
            set foundIt to false
            repeat with anItem in allItems
                try
                    if (name of anItem as text) is tName then
                        set desktop position of anItem to {{tX, tY}}
                        set successCount to successCount + 1
                        set foundIt to true
                        exit repeat
                    end if
                end try
            end repeat
            if not foundIt then set failedCount to failedCount + 1
        end repeat
    end tell
    return (successCount as text) & "|" & (failedCount as text)
    '''
    try:
        result = run_applescript(script)
        s, f = result.split("|")
        return int(s), int(f)
    except (RuntimeError, ValueError):
        return 0, len(positions)


# ─── Arbeitsumgebung: Hintergrund + Apps + Fenster ────────────────────

def _esc(text: str) -> str:
    """Escaped einen String für die Verwendung in AppleScript-Literalen."""
    return text.replace('\\', '\\\\').replace('"', '\\"')


def get_wallpaper() -> list[str]:
    """Liest die Hintergrundbild-Pfade aller Bildschirme (einer pro Desktop)."""
    script = '''
    tell application "System Events"
        set output to ""
        repeat with d in every desktop
            set output to output & (picture of d) & linefeed
        end repeat
        return output
    end tell
    '''
    try:
        raw = run_applescript(script)
    except RuntimeError:
        return []
    return [line for line in raw.splitlines() if line.strip()]


def set_wallpaper(wallpaper) -> bool:
    """Setzt den Desktop-Hintergrund.

    Akzeptiert einen einzelnen Pfad (string) – wird auf alle Bildschirme
    angewendet – oder eine Liste von Pfaden (einer pro Bildschirm).
    """
    # Rückwärtskompatibel: einzelner String
    if isinstance(wallpaper, str):
        path = wallpaper
        if not path or not Path(path).exists():
            return False
        try:
            run_applescript(
                f'tell application "System Events" to set picture of every desktop to "{_esc(path)}"'
            )
            return True
        except RuntimeError:
            return False

    paths = [p for p in (wallpaper or []) if p]
    if not paths:
        return False
    lines = ['tell application "System Events"', '  set ds to every desktop']
    for i, path in enumerate(paths, start=1):
        if not Path(path).exists():
            continue
        lines.append('  try')
        lines.append(f'    set picture of (item {i} of ds) to "{_esc(path)}"')
        lines.append('  end try')
    lines.append('end tell')
    try:
        run_applescript("\n".join(lines))
        return True
    except RuntimeError:
        return False


# ─── Multi-Monitor: Bildschirm-Anordnung erfassen ──────────────────────────

def get_display_layout() -> list[dict]:
    """Liefert die aktuelle Bildschirm-Anordnung (Anzahl, Position, Größe)."""
    layout = []
    try:
        for screen in NSScreen.screens():
            f = screen.frame()
            layout.append({
                "x": int(round(f.origin.x)),
                "y": int(round(f.origin.y)),
                "w": int(round(f.size.width)),
                "h": int(round(f.size.height)),
            })
    except Exception:
        pass
    return layout


def display_layouts_match(a: list, b: list) -> bool:
    """Vergleicht zwei Bildschirm-Anordnungen (Anzahl + Geometrie)."""
    if not a or not b:
        return True
    if len(a) != len(b):
        return False
    def norm(layout):
        return sorted((d.get("x"), d.get("y"), d.get("w"), d.get("h")) for d in layout)
    return norm(a) == norm(b)


def get_current_wifi_ssid() -> str | None:
    """Liefert die aktuell verbundene WLAN-SSID oder None.

    Nutzt zuerst ``networksetup``; fällt bei neueren macOS-Versionen auf
    ``ipconfig getsummary`` zurück. Gibt None zurück, wenn keine SSID
    ermittelt werden kann.
    """
    # Aktiven WLAN-Port ermitteln (meist en0/en1)
    ports = []
    try:
        out = subprocess.run(
            ["networksetup", "-listallhardwareports"],
            capture_output=True, text=True, timeout=5
        ).stdout
        blocks = out.split("Hardware Port:")
        for b in blocks:
            if "Wi-Fi" in b or "AirPort" in b:
                for line in b.splitlines():
                    line = line.strip()
                    if line.startswith("Device:"):
                        ports.append(line.split(":", 1)[1].strip())
    except Exception:
        pass
    if not ports:
        ports = ["en0", "en1"]

    for dev in ports:
        try:
            out = subprocess.run(
                ["networksetup", "-getairportnetwork", dev],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            if ":" in out and "not associated" not in out.lower():
                ssid = out.split(":", 1)[1].strip()
                if ssid:
                    return ssid
        except Exception:
            pass
        # Fallback für neuere macOS-Versionen
        try:
            out = subprocess.run(
                ["ipconfig", "getsummary", dev],
                capture_output=True, text=True, timeout=5
            ).stdout
            for line in out.splitlines():
                line = line.strip()
                if line.startswith("SSID :") or line.startswith("SSID:"):
                    ssid = line.split(":", 1)[1].strip()
                    if ssid:
                        return ssid
        except Exception:
            pass
    return None


# ─── Systemzustand (Erscheinungsbild, Lautstärke, Helligkeit, Fokus, Dock) ──

def get_dark_mode():
    """Liest, ob der dunkle Modus aktiv ist. Gibt True/False oder None zurück."""
    try:
        raw = run_applescript(
            'tell application "System Events" to tell appearance preferences '
            'to return dark mode'
        ).strip().lower()
    except RuntimeError:
        return None
    if raw in ("true", "wahr", "1"):
        return True
    if raw in ("false", "falsch", "0"):
        return False
    return None


def set_dark_mode(dark) -> bool:
    """Schaltet den dunklen Modus systemweit ein/aus."""
    if dark is None:
        return False
    val = "true" if dark else "false"
    try:
        run_applescript(
            'tell application "System Events" to tell appearance preferences '
            f'to set dark mode to {val}'
        )
        return True
    except RuntimeError:
        return False


def get_volume():
    """Liest die Ausgabelautstärke (0–100) oder None bei Fehler."""
    try:
        raw = run_applescript('return output volume of (get volume settings)').strip()
        return int(raw)
    except (RuntimeError, ValueError):
        return None


def set_volume(vol) -> bool:
    """Setzt die Ausgabelautstärke (0–100)."""
    if vol is None:
        return False
    try:
        v = max(0, min(100, int(vol)))
        run_applescript(f'set volume output volume {v}')
        return True
    except (RuntimeError, ValueError):
        return False


def get_brightness():
    """Liest die Bildschirmhelligkeit (0.0–1.0) via ``brightness``-CLI.

    Gibt None zurück, wenn das Tool nicht installiert ist (``brew install
    brightness``). Helligkeit lässt sich auf macOS nicht zuverlässig ohne
    Zusatztool auslesen/setzen.
    """
    exe = shutil.which("brightness")
    if not exe:
        return None
    try:
        out = subprocess.run([exe, "-l"], capture_output=True, text=True, timeout=5)
        for line in out.stdout.splitlines():
            if "brightness" in line.lower():
                # Format: "display 0: brightness 0.812500"
                return float(line.strip().split()[-1])
    except (subprocess.SubprocessError, ValueError, OSError):
        return None
    return None


def set_brightness(value) -> bool:
    """Setzt die Bildschirmhelligkeit (0.0–1.0) via ``brightness``-CLI."""
    if value is None:
        return False
    exe = shutil.which("brightness")
    if not exe:
        return False
    try:
        v = max(0.0, min(1.0, float(value)))
        subprocess.run([exe, str(v)], capture_output=True, timeout=5)
        return True
    except (subprocess.SubprocessError, ValueError, OSError):
        return False


def get_do_not_disturb():
    """Liest den Nicht-stören-/Fokus-Status. Gibt True/False oder None zurück.

    Hinweis: Ab macOS Monterey lässt sich der Fokus-Status nur eingeschränkt
    auslesen. Es wird der zuletzt bekannte Wert aus der ControlCenter-
    Einstellung versucht.
    """
    try:
        out = subprocess.run(
            ["defaults", "-currentHost", "read",
             "com.apple.controlcenter", "NSStatusItem Visible FocusModes"],
            capture_output=True, text=True, timeout=5
        )
        # Dieser Schlüssel sagt nur etwas über die Menüleisten-Anzeige aus;
        # der echte Fokus-Status ist nicht öffentlich lesbar.
        _ = out
    except (subprocess.SubprocessError, OSError):
        pass
    return None


def set_do_not_disturb(enabled) -> bool:
    """Schaltet 'Nicht stören' ein/aus (best effort).

    Versucht zuerst eine gleichnamige Kurzbefehl-Aktion (Shortcuts) und fällt
    sonst auf die ältere ``defaults``-Methode zurück. Auf neueren macOS-
    Versionen ist das systemseitig nur eingeschränkt möglich.
    """
    if enabled is None:
        return False
    shortcut = "Fokus ein" if enabled else "Fokus aus"
    try:
        sc = shutil.which("shortcuts")
        if sc:
            res = subprocess.run([sc, "run", shortcut],
                                 capture_output=True, timeout=10)
            if res.returncode == 0:
                return True
    except (subprocess.SubprocessError, OSError):
        pass
    # Fallback für ältere macOS-Versionen (vor Monterey)
    try:
        val = "true" if enabled else "false"
        subprocess.run(["defaults", "-currentHost", "write",
                        "com.apple.notificationcenterui", "doNotDisturb", "-bool", val],
                       capture_output=True, timeout=5)
        subprocess.run(["killall", "NotificationCenter"],
                       capture_output=True, timeout=5)
        return True
    except (subprocess.SubprocessError, OSError):
        return False


def get_dock_settings():
    """Liest relevante Dock-Einstellungen (Position, Größe, Auto-Ausblenden)."""
    def _read(key, typ):
        try:
            out = subprocess.run(["defaults", "read", "com.apple.dock", key],
                                 capture_output=True, text=True, timeout=5)
            if out.returncode != 0:
                return None
            raw = out.stdout.strip()
            if typ is bool:
                return raw in ("1", "true", "YES")
            if typ is int:
                return int(float(raw))
            return raw
        except (subprocess.SubprocessError, ValueError, OSError):
            return None
    return {
        "orientation": _read("orientation", str),     # left|bottom|right
        "tilesize": _read("tilesize", int),           # Icon-Größe
        "autohide": _read("autohide", bool),
        "magnification": _read("magnification", bool),
    }


def set_dock_settings(settings) -> bool:
    """Setzt Dock-Einstellungen und startet das Dock neu."""
    if not settings:
        return False
    changed = False
    try:
        for key, typ, val in (
            ("orientation", "string", settings.get("orientation")),
            ("tilesize", "int", settings.get("tilesize")),
            ("autohide", "bool", settings.get("autohide")),
            ("magnification", "bool", settings.get("magnification")),
        ):
            if val is None:
                continue
            if typ == "bool":
                arg = "true" if val else "false"
            else:
                arg = str(val)
            subprocess.run(["defaults", "write", "com.apple.dock", key,
                            f"-{typ}", arg], capture_output=True, timeout=5)
            changed = True
        if changed:
            subprocess.run(["killall", "Dock"], capture_output=True, timeout=5)
        return changed
    except (subprocess.SubprocessError, OSError):
        return False


def get_desktop_view_settings():
    """Liest die Anzeige-Optionen des Desktops (Icon-Größe, Anordnung, Raster)."""
    script = '''
    tell application "Finder"
        set o to icon view options of desktop
        set ag to (arrangement of o) as string
        set isize to (icon size of o) as string
        return ag & "||" & isize
    end tell
    '''
    try:
        raw = run_applescript(script).strip()
    except RuntimeError:
        return None
    parts = raw.split("||")
    if len(parts) != 2:
        return None
    try:
        icon_size = int(float(parts[1]))
    except ValueError:
        icon_size = None
    return {"arrangement": parts[0].strip(), "icon_size": icon_size}


def set_desktop_view_settings(settings) -> bool:
    """Setzt Icon-Größe und Anordnung der Desktop-Symbole."""
    if not settings:
        return False
    lines = ['tell application "Finder"', '  set o to icon view options of desktop']
    arr = settings.get("arrangement")
    size = settings.get("icon_size")
    if arr:
        # AppleScript-Konstante, z. B. "name", "arranged by name" etc.
        lines.append('  try')
        lines.append(f'    set arrangement of o to {arr}')
        lines.append('  end try')
    if size:
        lines.append(f'  set icon size of o to {int(size)}')
    lines.append('end tell')
    try:
        run_applescript("\n".join(lines))
        return True
    except RuntimeError:
        return False


# Registry aller "Systemzustand"-Optionen: key -> Definition.
# Jede Option hat ein Label (de, en), eine Lese- und eine Schreibfunktion.
SYSTEM_STATE_OPTIONS = {
    "appearance": {
        "label": ("Erscheinungsbild (hell/dunkel)", "Appearance (light/dark)"),
        "get": get_dark_mode,
        "set": set_dark_mode,
    },
    "volume": {
        "label": ("Lautstärke", "Volume"),
        "get": get_volume,
        "set": set_volume,
    },
    "brightness": {
        "label": ("Bildschirmhelligkeit", "Screen brightness"),
        "get": get_brightness,
        "set": set_brightness,
    },
    "dnd": {
        "label": ("Nicht stören / Fokus", "Do Not Disturb / Focus"),
        "get": get_do_not_disturb,
        "set": set_do_not_disturb,
    },
    "dock": {
        "label": ("Dock-Konfiguration", "Dock configuration"),
        "get": get_dock_settings,
        "set": set_dock_settings,
    },
    "desktop_view": {
        "label": ("Icon-Anzeige (Größe/Anordnung)", "Icon view (size/arrangement)"),
        "get": get_desktop_view_settings,
        "set": set_desktop_view_settings,
    },
}


def capture_system_state(keys) -> dict:
    """Erfasst die Werte der angegebenen Systemzustand-Optionen."""
    state = {}
    for key in keys or []:
        opt = SYSTEM_STATE_OPTIONS.get(key)
        if not opt:
            continue
        try:
            value = opt["get"]()
        except Exception:
            value = None
        if value is not None:
            state[key] = value
    return state


def restore_system_state(state) -> None:
    """Stellt die gespeicherten Systemzustand-Werte wieder her."""
    for key, value in (state or {}).items():
        opt = SYSTEM_STATE_OPTIONS.get(key)
        if not opt:
            continue
        try:
            opt["set"](value)
        except Exception:
            pass


# Apps, die nicht erfasst/gestartet werden sollen
_APP_BLACKLIST_BUNDLES = {"com.apple.finder", "com.iconguard.app", "com.desktopprofilemanager.app"}
_APP_BLACKLIST_NAMES = {APP_NAME, "Finder"}


def get_running_apps() -> list[dict]:
    """Liefert die aktuell sichtbaren (regulären) Apps via NSWorkspace."""
    apps = []
    for ra in NSWorkspace.sharedWorkspace().runningApplications():
        if ra.activationPolicy() != NSApplicationActivationPolicyRegular:
            continue
        name = ra.localizedName()
        bundle_id = ra.bundleIdentifier()
        url = ra.bundleURL()
        path = url.path() if url else None
        if not name or not path:
            continue
        if bundle_id in _APP_BLACKLIST_BUNDLES or name in _APP_BLACKLIST_NAMES:
            continue
        apps.append({"name": name, "bundle_id": bundle_id, "path": path})
    return apps


def get_app_windows() -> dict:
    """Liefert pro Prozessname eine Liste der Fenster-Geometrien.

    Benötigt die Bedienungshilfen-Berechtigung (Accessibility). Ohne diese
    Berechtigung wird ein leeres Dict zurückgegeben.
    """
    script = '''
    tell application "System Events"
        set output to ""
        repeat with proc in (every process whose background only is false)
            set procName to name of proc
            try
                repeat with w in windows of proc
                    set p to position of w
                    set s to size of w
                    set output to output & procName & "||" & (item 1 of p) & "||" & (item 2 of p) & "||" & (item 1 of s) & "||" & (item 2 of s) & linefeed
                end repeat
            end try
        end repeat
        return output
    end tell
    '''
    try:
        raw = run_applescript(script)
    except RuntimeError:
        return {}
    result: dict[str, list] = {}
    for line in raw.splitlines():
        parts = line.split("||")
        if len(parts) != 5:
            continue
        try:
            x, y, w, h = (int(float(parts[i])) for i in range(1, 5))
        except ValueError:
            continue
        result.setdefault(parts[0], []).append({"x": x, "y": y, "w": w, "h": h})
    return result


def capture_apps(exclusions=None) -> list[dict]:
    """Erfasst laufende Apps inkl. Fensterposition/-größe.

    Apps, deren Name in ``exclusions`` steht, werden ausgelassen.
    """
    excluded = set(exclusions or [])
    apps = [a for a in get_running_apps() if a["name"] not in excluded]
    windows = get_app_windows()
    for app in apps:
        app["windows"] = windows.get(app["name"], [])
    return apps


def restore_windows(apps: list[dict]) -> None:
    """Stellt die Fensterpositionen/-größen der angegebenen Apps wieder her."""
    for app in apps:
        wins = app.get("windows") or []
        if not wins:
            continue
        name = _esc(app["name"])
        lines = ['tell application "System Events"', f'  tell process "{name}"']
        for i, w in enumerate(wins, start=1):
            lines.append('    try')
            lines.append(f'      set position of window {i} to {{{int(w["x"])}, {int(w["y"])}}}')
            lines.append(f'      set size of window {i} to {{{int(w["w"])}, {int(w["h"])}}}')
            lines.append('    end try')
        lines.append('  end tell')
        lines.append('end tell')
        try:
            run_applescript("\n".join(lines))
        except RuntimeError:
            pass


def _set_apps_visible(names, visible: bool) -> None:
    """Setzt die Sichtbarkeit (ein-/ausblenden) der Prozesse via System Events.

    Nutzt die ``visible``-Eigenschaft eines Prozesses in System Events – das
    funktioniert (anders als ``NSRunningApplication.hide()/unhide()``)
    zuverlässig aus einer Hintergrund-App heraus. Benötigt die
    Bedienungshilfen-Berechtigung, die für die Fensterpositionierung ohnehin
    erforderlich ist.
    """
    names = [n for n in (names or []) if n]
    if not names:
        return
    val = "true" if visible else "false"
    lines = ['tell application "System Events"']
    for n in names:
        lines.append('  try')
        lines.append(f'    set visible of process "{_esc(n)}" to {val}')
        lines.append('  end try')
    lines.append('end tell')
    try:
        run_applescript("\n".join(lines))
    except RuntimeError:
        pass


def launch_apps(apps: list[dict], stagger_delay: float = 1.5) -> int:
    """Startet die angegebenen Apps gestaffelt und stellt ihre Fenster wieder her.

    Apps werden nacheinander mit einer kleinen Verzögerung gestartet, damit
    schwergewichtige Programme das System nicht gleichzeitig auslasten. Bereits
    laufende Apps werden nicht neu gestartet, sondern (falls ausgeblendet)
    wieder eingeblendet.
    """
    launched = 0
    running_names = {a["name"] for a in get_running_apps()}
    to_unhide = []
    for app in apps:
        name = app.get("name")
        target = app.get("path") or name
        if not target:
            continue
        if name in running_names:
            # Bereits laufend -> nur wieder einblenden
            to_unhide.append(name)
            continue
        try:
            subprocess.run(
                ["open", "-a", target],
                capture_output=True, timeout=20,
            )
            launched += 1
        except (subprocess.SubprocessError, OSError):
            continue
        time.sleep(stagger_delay)
    # Bereits laufende Profil-Apps wieder einblenden
    if to_unhide:
        _set_apps_visible(to_unhide, True)
    # Fenster erst positionieren, wenn die Apps Zeit zum Öffnen hatten
    if any(app.get("windows") for app in apps):
        time.sleep(3)
        restore_windows(apps)
    return launched


def hide_other_apps(keep_apps: list[dict]) -> int:
    """Blendet alle laufenden Apps aus, die nicht zum Profil gehören.

    Die Apps werden nicht beendet, sondern nur ausgeblendet (wie ⌘H). Das
    Ausblenden erfolgt über die ``visible``-Eigenschaft in System Events, da
    ``NSRunningApplication.hide()`` aus einer Hintergrund-App heraus nicht
    zuverlässig wirkt. Apps aus ``keep_apps`` sowie die Blacklist (Finder,
    eigene App) bleiben sichtbar. Gibt die Anzahl der ausgeblendeten Apps
    zurück.
    """
    keep_bundles = {a.get("bundle_id") for a in keep_apps if a.get("bundle_id")}
    keep_names = {a.get("name") for a in keep_apps if a.get("name")}
    own_pid = os.getpid()
    to_hide = []
    for ra in NSWorkspace.sharedWorkspace().runningApplications():
        if ra.activationPolicy() != NSApplicationActivationPolicyRegular:
            continue
        if int(ra.processIdentifier()) == own_pid:
            continue
        bundle_id = ra.bundleIdentifier()
        name = ra.localizedName()
        if bundle_id in _APP_BLACKLIST_BUNDLES or name in _APP_BLACKLIST_NAMES:
            continue
        if bundle_id in keep_bundles or name in keep_names:
            continue
        if ra.isHidden():
            continue
        if name:
            to_hide.append(name)
    _set_apps_visible(to_hide, False)
    return len(to_hide)


def quit_other_apps(keep_apps: list[dict]) -> int:
    """Beendet alle laufenden Apps, die nicht zum Profil gehören.

    Im Gegensatz zu :func:`hide_other_apps` werden die Apps regulär beendet
    (wie ⌘Q). Apps aus ``keep_apps`` sowie die Blacklist (Finder, eigene App)
    bleiben unberührt. Gibt die Anzahl der beendeten Apps zurück.
    """
    keep_bundles = {a.get("bundle_id") for a in keep_apps if a.get("bundle_id")}
    keep_names = {a.get("name") for a in keep_apps if a.get("name")}
    own_pid = os.getpid()
    count = 0
    for ra in NSWorkspace.sharedWorkspace().runningApplications():
        if ra.activationPolicy() != NSApplicationActivationPolicyRegular:
            continue
        if int(ra.processIdentifier()) == own_pid:
            continue
        bundle_id = ra.bundleIdentifier()
        name = ra.localizedName()
        if bundle_id in _APP_BLACKLIST_BUNDLES or name in _APP_BLACKLIST_NAMES:
            continue
        if bundle_id in keep_bundles or name in keep_names:
            continue
        try:
            if ra.terminate():
                count += 1
        except Exception:
            pass
    return count


# ─── Desktop-Sichtbarkeit ────────────────────────────────────────────

def get_desktop_path() -> Path:
    return Path.home() / "Desktop"


def get_all_desktop_items() -> list[dict]:
    """Gibt alle Desktop-Items zurück mit Name und Hidden-Status."""
    desktop = get_desktop_path()
    items = []
    for item in desktop.iterdir():
        if item.name.startswith("."):
            continue
        try:
            st = item.stat()
            is_hidden = bool(st.st_flags & stat.UF_HIDDEN)
            items.append({"name": item.name, "hidden": is_hidden})
        except OSError:
            pass
    return sorted(items, key=lambda x: x["name"])


def get_hidden_items() -> list[str]:
    """Gibt eine Liste aller versteckten Dateien auf dem Desktop zurück."""
    return [i["name"] for i in get_all_desktop_items() if i["hidden"]]


def hide_item(name: str) -> bool:
    path = get_desktop_path() / name
    if not path.exists():
        return False
    try:
        st = path.stat()
        os.chflags(path, st.st_flags | stat.UF_HIDDEN)
        return True
    except OSError:
        return False


def unhide_item(name: str) -> bool:
    path = get_desktop_path() / name
    if not path.exists():
        return False
    try:
        st = path.stat()
        os.chflags(path, st.st_flags & ~stat.UF_HIDDEN)
        return True
    except OSError:
        return False


# ─── Profil-Verwaltung ────────────────────────────────────────────

def get_profile_path(name: str) -> Path:
    safe = "".join(c for c in name if c.isalnum() or c in "-_ ")
    if not safe:
        raise ValueError("Ungültiger Profilname.")
    return PROFILES_DIR / f"{safe}.json"


def _atomic_write_text(path: Path, text: str):
    """Schreibt Text atomar: erst in eine temporäre Datei, dann umbenennen.

    Verhindert beschädigte oder leere (0-Byte) Profildateien, falls der
    Schreibvorgang unterbrochen wird (z. B. App-Beenden während des
    Hintergrund-Speicherns).
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def list_profiles() -> list:
    if not PROFILES_DIR.exists():
        return []
    profiles = []
    for p in sorted(PROFILES_DIR.glob("*.json")):
        if p.name.startswith("_"):
            continue
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            hidden = data.get("hidden", [])
            settings = data.get("settings") or {}
            profiles.append({
                "name": data.get("profile", p.stem),
                "count": data.get("icon_count", 0),
                "hidden_count": len(hidden),
                "app_count": len(data.get("apps", [])),
                "has_wallpaper": bool(data.get("wallpaper")),
                "saved_at": data.get("saved_at", ""),
                "emoji": settings.get("emoji", "") or "",
                "wifi_ssid": settings.get("wifi_ssid", "") or "",
                "path": p,
            })
        except (json.JSONDecodeError, ValueError):
            pass
    return profiles


def save_profile(name: str, app_exclusions=None, *,
                 with_positions: bool = True,
                 with_hidden: bool = True,
                 with_wallpaper: bool = True,
                 with_apps: bool = True,
                 included_apps=None,
                 system_state_keys=None,
                 emoji: str = "",
                 wifi_ssid: str = "") -> tuple:
    """Speichert ein Profil mit den ausgewählten Inhalten.

    ``with_*`` bestimmen, welche Daten erfasst werden. ``included_apps``
    ist – falls gesetzt – eine Whitelist der App-Namen, die ins Profil
    aufgenommen werden; ist sie ``None``, greift die globale ``app_exclusions``
    Liste. ``system_state_keys`` ist eine Liste der zu erfassenden
    Systemzustand-Optionen (siehe ``SYSTEM_STATE_OPTIONS``). Die getroffene
    Auswahl wird unter ``settings`` im Profil gesichert, sodass sie beim
    Wiederherstellen Vorrang vor den globalen Schaltern hat.
    """
    PROFILES_DIR.mkdir(exist_ok=True)
    positions = get_icon_positions() if with_positions else {}
    hidden = get_hidden_items() if with_hidden else []
    wallpaper = get_wallpaper() if with_wallpaper else None
    display_layout = get_display_layout()
    system_state_keys = list(system_state_keys or [])
    system_state = capture_system_state(system_state_keys)

    if with_apps:
        if included_apps is not None:
            included_set = set(included_apps)
            exclusions = [a["name"] for a in get_running_apps()
                          if a["name"] not in included_set]
        else:
            exclusions = app_exclusions
        apps = capture_apps(exclusions)
    else:
        apps = []

    if (not positions and not hidden and not wallpaper and not apps
            and not system_state):
        return 0, "Keine Daten zum Speichern gefunden"
    path = get_profile_path(name)
    data = {
        "profile": name,
        "saved_at": datetime.now().isoformat(),
        "icon_count": len(positions) + len(hidden),
        "positions": positions,
        "hidden": hidden,
        "wallpaper": wallpaper,
        "apps": apps,
        "system_state": system_state,
        "display_layout": display_layout,
        "settings": {
            "capture_positions": with_positions,
            "capture_hidden": with_hidden,
            "capture_wallpaper": with_wallpaper,
            "capture_apps": with_apps,
            "restore_positions": with_positions,
            "restore_wallpaper": with_wallpaper,
            "restore_apps": with_apps,
            "included_apps": list(included_apps) if included_apps is not None else None,
            "system_state_keys": system_state_keys,
            "emoji": emoji or "",
            "wifi_ssid": wifi_ssid or "",
        },
    }
    _atomic_write_text(path, json.dumps(data, indent=2, ensure_ascii=False))
    return len(positions) + len(hidden), path


def restore_profile(name: str, include_wallpaper: bool = True,
                    include_apps: bool = False,
                    hide_others: bool = False,
                    quit_others: bool = False,
                    launch_delay: float = 1.5) -> tuple:
    path = get_profile_path(name)
    if not path.exists():
        return 0, 0, f"Profil '{name}' nicht gefunden", None
    data = json.loads(path.read_text(encoding="utf-8"))
    hidden_list = data.get("hidden", [])

    # Im Profil gespeicherte Einstellungen haben Vorrang vor den globalen
    # Schaltern (z. B. bestimmt jedes Profil selbst, ob Hintergrund/Apps
    # wiederhergestellt werden). Ältere Profile ohne "settings" nutzen
    # weiterhin die übergebenen globalen Werte.
    settings = data.get("settings") or {}
    restore_positions = settings.get("restore_positions", True)
    if "restore_wallpaper" in settings:
        include_wallpaper = settings["restore_wallpaper"]
    if "restore_apps" in settings:
        include_apps = settings["restore_apps"]

    # Sichtbarkeit wiederherstellen
    all_items = get_all_desktop_items()
    for item in all_items:
        if item["name"] in hidden_list:
            hide_item(item["name"])
        else:
            unhide_item(item["name"])

    if restore_positions:
        success, failed = set_icon_positions(data.get("positions", {}))
    else:
        success, failed = 0, 0

    # Hintergrund wiederherstellen
    if include_wallpaper and data.get("wallpaper"):
        set_wallpaper(data["wallpaper"])

    # Apps starten und Fenster wiederherstellen
    profile_apps = data.get("apps") or []
    if include_apps and profile_apps:
        launch_apps(profile_apps, stagger_delay=launch_delay)

    # Nicht zum Profil gehörende Apps ausblenden oder beenden
    if quit_others:
        quit_other_apps(profile_apps)
    elif hide_others:
        hide_other_apps(profile_apps)

    # Systemzustand (Erscheinungsbild, Lautstärke, Dock …) wiederherstellen
    restore_system_state(data.get("system_state") or {})

    # Multi-Monitor: Warnen, falls sich die Bildschirm-Anordnung geändert hat
    warning = None
    saved_layout = data.get("display_layout") or []
    if restore_positions and saved_layout:
        if not display_layouts_match(saved_layout, get_display_layout()):
            warning = L(
                "Bildschirm-Anordnung weicht ab – Symbolpositionen passen evtl. nicht.",
                "Display arrangement differs – icon positions may not match.",
            )

    return success, failed, None, warning


# ─── Konfiguration ────────────────────────────────────────────────

def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            saved = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            config = {**DEFAULT_CONFIG, **saved}
            return config
        except (json.JSONDecodeError, ValueError):
            pass
    return dict(DEFAULT_CONFIG)


def save_config(config: dict):
    PROFILES_DIR.mkdir(exist_ok=True)
    _atomic_write_text(CONFIG_PATH, json.dumps(config, indent=2))


# ─── LaunchAgent ──────────────────────────────────────────────────

LAUNCH_AGENT_LABEL = "com.desktopprofilemanager.app"
LAUNCH_AGENT_PATH = Path.home() / "Library" / "LaunchAgents" / f"{LAUNCH_AGENT_LABEL}.plist"
# Altes Label aus früheren Versionen (für Migration/Aufräumen)
OLD_LAUNCH_AGENT_LABEL = "com.iconguard.app"
OLD_LAUNCH_AGENT_PATH = Path.home() / "Library" / "LaunchAgents" / f"{OLD_LAUNCH_AGENT_LABEL}.plist"
# Noch ältere LaunchAgent-Labels aus der allerersten Projektphase, die heute ins
# Leere zeigen (umbenannte Skripte) und daher entfernt werden müssen.
OLD_LAUNCH_AGENT_LABELS = ["com.iconguard.app", "com.desktop-icon-manager.app"]
# Alter Login-Item-Name (System Events) des Vorgängers „IconGuard"
OLD_LOGIN_ITEM_NAME = "IconGuard"


def get_app_bundle_path() -> str | None:
    """Gibt den Pfad zum .app-Bundle zurück, falls wir darin laufen."""
    exe = Path(sys.executable).resolve()
    # py2app-Bundle: .../Desktop Profile Manager.app/Contents/MacOS/...
    for parent in exe.parents:
        if parent.suffix == ".app" and (parent / "Contents" / "MacOS").is_dir():
            return str(parent)
    return None


def get_app_script_path() -> str:
    """Gibt den Pfad zum Startskript zurück."""
    return str(Path(__file__).resolve())


def get_python_path() -> str:
    """Gibt den Pfad zum Python-Executable in der venv zurück."""
    venv_python = Path(__file__).resolve().parent / ".venv" / "bin" / "python3"
    if venv_python.exists():
        return str(venv_python)
    return sys.executable


def is_autostart_enabled() -> bool:
    return LAUNCH_AGENT_PATH.exists()


def _remove_old_login_item() -> bool:
    """Entfernt das alte „IconGuard"-Login-Item (macOS-Anmeldeobjekt).

    Gibt ``True`` zurück, wenn tatsächlich ein Eintrag entfernt wurde.
    """
    try:
        check = subprocess.run(
            ["osascript", "-e",
             f'tell application "System Events" to count '
             f'(every login item whose name is "{OLD_LOGIN_ITEM_NAME}")'],
            capture_output=True, text=True, timeout=10)
        count = (check.stdout or "").strip()
        if not count.isdigit() or int(count) <= 0:
            return False
        subprocess.run(
            ["osascript", "-e",
             f'tell application "System Events" to delete '
             f'(every login item whose name is "{OLD_LOGIN_ITEM_NAME}")'],
            capture_output=True, text=True, timeout=10)
        return True
    except Exception:
        return False


def _cleanup_old_autostart():
    """Entfernt Autostart-Reste des Vorgängers (LaunchAgents + Login-Item)."""
    agents_dir = Path.home() / "Library" / "LaunchAgents"
    for label in OLD_LAUNCH_AGENT_LABELS:
        old_path = agents_dir / f"{label}.plist"
        if old_path.exists():
            subprocess.run(["launchctl", "unload", str(old_path)],
                           capture_output=True)
            try:
                old_path.unlink()
            except OSError:
                pass
    _remove_old_login_item()


def enable_autostart():
    _cleanup_old_autostart()
    app_bundle = get_app_bundle_path()

    if app_bundle:
        # Als .app-Bundle: mit 'open' starten
        program_args = f"""    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>{app_bundle}</string>
    </array>"""
    else:
        # Entwicklungsmodus: Python + Skript direkt
        python_path = get_python_path()
        script_path = get_app_script_path()
        program_args = f"""    <array>
        <string>{python_path}</string>
        <string>{script_path}</string>
    </array>"""

    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
{program_args}
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>{PROFILES_DIR}/app.log</string>
    <key>StandardErrorPath</key>
    <string>{PROFILES_DIR}/app.log</string>
</dict>
</plist>
"""
    LAUNCH_AGENT_PATH.parent.mkdir(parents=True, exist_ok=True)
    LAUNCH_AGENT_PATH.write_text(plist_content, encoding="utf-8")
    subprocess.run(["launchctl", "load", str(LAUNCH_AGENT_PATH)],
                   capture_output=True)


def disable_autostart():
    _cleanup_old_autostart()
    if LAUNCH_AGENT_PATH.exists():
        subprocess.run(["launchctl", "unload", str(LAUNCH_AGENT_PATH)],
                       capture_output=True)
        LAUNCH_AGENT_PATH.unlink()


# ─── Menüleisten-App ──────────────────────────────────────────────

class SleepWakeObserver(NSObject):
    """Beobachtet Sleep/Wake-Events vom System."""
    def initWithApp_(self, app):
        self = objc.super(SleepWakeObserver, self).init()
        if self is None:
            return None
        self._app = app
        return self

    def handleWakeNotification_(self, notification):
        """Wird aufgerufen wenn der Mac aus dem Ruhemodus aufwacht."""
        if self._app.config.get("restore_on_wake", True):
            self._app._restore_after_wake()





class VisibilityWindowDelegate(NSObject):
    """Delegate für das Sichtbarkeits-Fenster."""

    def initWithCheckboxes_window_app_(self, checkboxes, window, app):
        self = objc.super(VisibilityWindowDelegate, self).init()
        if self is None:
            return None
        self._checkboxes = checkboxes
        self._window = window
        self._app = app
        return self

    def onSelectAll_(self, sender):
        """Setzt alle Checkboxen auf 'sichtbar'."""
        for _name, cb in self._checkboxes:
            cb.setState_(NSControlStateValueOn)

    def onApply_(self, sender):
        """Wendet die Änderungen an und schließt das Fenster."""
        changes = []
        for name, cb in self._checkboxes:
            should_be_visible = (cb.state() == NSControlStateValueOn)
            changes.append((name, should_be_visible))

        self._window.close()

        # Zurück zur Accessory-App (kein Dock-Icon)
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

        def task():
            hidden_count = 0
            shown_count = 0
            for name, should_be_visible in changes:
                if should_be_visible:
                    if unhide_item(name):
                        shown_count += 1
                else:
                    if hide_item(name):
                        hidden_count += 1
            parts = []
            if hidden_count:
                parts.append(L(f"{hidden_count} versteckt", f"{hidden_count} hidden"))
            if shown_count:
                parts.append(L(f"{shown_count} eingeblendet", f"{shown_count} shown"))
            if parts:
                rumps.notification(APP_NAME, L("Sichtbarkeit geändert", "Visibility changed"), ", ".join(parts))
            self._app._build_menu()

        threading.Thread(target=task, daemon=True).start()

    def windowWillClose_(self, notification):
        """Wird aufgerufen wenn das Fenster geschlossen wird."""
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        self._app._visibility_window = None


class AppSelectionWindowDelegate(NSObject):
    """Delegate für das App-Auswahl-Fenster (Auto-Start-Ausschlüsse)."""

    def initWithCheckboxes_window_app_(self, checkboxes, window, app):
        self = objc.super(AppSelectionWindowDelegate, self).init()
        if self is None:
            return None
        self._checkboxes = checkboxes
        self._window = window
        self._app = app
        return self

    def onSelectAll_(self, sender):
        """Aktiviert alle Apps (keine Ausschlüsse)."""
        for _name, cb in self._checkboxes:
            cb.setState_(NSControlStateValueOn)

    def onApply_(self, sender):
        """Speichert die abgewählten Apps als Ausschlussliste."""
        exclusions = [
            name for name, cb in self._checkboxes
            if cb.state() == NSControlStateValueOff
        ]
        self._window.close()
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

        self._app.config["app_exclusions"] = exclusions
        save_config(self._app.config)
        if exclusions:
            rumps.notification(
                APP_NAME, L("App-Auswahl gespeichert", "App selection saved"),
                L(f"{len(exclusions)} App(s) werden beim Speichern ausgelassen.",
                  f"{len(exclusions)} app(s) will be excluded when saving.")
            )
        else:
            rumps.notification(
                APP_NAME, L("App-Auswahl gespeichert", "App selection saved"),
                L("Alle laufenden Apps werden in Profile aufgenommen.",
                  "All running apps will be included in profiles.")
            )

    def windowWillClose_(self, notification):
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        self._app._app_window = None


class ProfileSetupWindowDelegate(NSObject):
    """Delegate für das Setup-Fenster beim Erstellen eines neuen Profils.

    Sammelt Profilname, die Auswahl der zu speichernden Inhalte
    (Positionen, versteckte Icons, Hintergrund, Apps) sowie die konkrete
    App-Whitelist und löst anschließend das Speichern aus.
    """

    def initWithFields_window_app_(self, fields, window, app):
        self = objc.super(ProfileSetupWindowDelegate, self).init()
        if self is None:
            return None
        self._name_field = fields["name_field"]
        self._emoji_field = fields.get("emoji_field")
        self._wifi_field = fields.get("wifi_field")
        self._options = fields["options"]            # dict: key -> NSButton
        self._system_options = fields.get("system_options") or {}  # key -> NSButton
        self._app_checkboxes = fields["app_checkboxes"]  # list of (name, cb)
        self._edit_name = fields.get("edit_name")    # None = neu, sonst Bearbeiten
        self._window = window
        self._app = app
        return self

    def onSelectAllApps_(self, sender):
        for _name, cb in self._app_checkboxes:
            cb.setState_(NSControlStateValueOn)

    def onUseCurrentWifi_(self, sender):
        if self._wifi_field is not None:
            self._wifi_field.setStringValue_(get_current_wifi_ssid() or "")

    def onPickEmoji_(self, sender):
        # macOS Emoji-/Zeichenauswahl per Mausklick öffnen.
        try:
            if self._emoji_field is not None and self._window is not None:
                self._window.makeFirstResponder_(self._emoji_field)
            NSApp.orderFrontCharacterPalette_(sender)
        except Exception:
            pass

    def onCreate_(self, sender):
        name = str(self._name_field.stringValue()).strip()
        if not name:
            rumps.alert(title=L("Profilname fehlt", "Profile name missing"),
                        message=L("Bitte einen Namen für das Profil eingeben.",
                                  "Please enter a name for the profile."),
                        ok="OK")
            return

        settings = {
            key: (cb.state() == NSControlStateValueOn)
            for key, cb in self._options.items()
        }
        system_state_keys = [
            key for key, cb in self._system_options.items()
            if cb.state() == NSControlStateValueOn
        ]
        settings["system_state_keys"] = system_state_keys
        if self._emoji_field is not None:
            settings["emoji"] = str(self._emoji_field.stringValue()).strip()
        if self._wifi_field is not None:
            settings["wifi_ssid"] = str(self._wifi_field.stringValue()).strip()
        included_apps = [
            n for n, cb in self._app_checkboxes
            if cb.state() == NSControlStateValueOn
        ]

        self._window.close()
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        if self._edit_name:
            self._app._apply_profile_edit(
                self._edit_name, name, settings, included_apps
            )
        else:
            self._app._do_save_with_settings(name, settings, included_apps)

    def windowWillClose_(self, notification):
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        self._app._setup_window = None


class DesktopIconManagerApp(rumps.App):
    def __init__(self):
        super().__init__(
            APP_NAME,
            icon=APP_ICON,
            title=None,
            quit_button=None,
        )
        self.config = load_config()
        resolve_language(self.config)
        self.auto_timer = None
        self._wake_observer = None
        self._visibility_window = None
        self._visibility_delegate = None
        self._app_window = None
        self._app_delegate = None
        self._setup_window = None
        self._setup_delegate = None
        self._last_check_time = time.time()
        self._screen_was_locked = False
        self._hotkey_monitor = None
        self._auto_switch_timer = None
        self._last_auto_switch = None
        self._active_profile = None
        self._build_menu()
        self._migrate_old_iconguard()
        if self.config["auto_restore_enabled"]:
            self._start_auto_restore()
        if self.config.get("restore_on_login", True):
            self._restore_on_login()
        if self.config.get("hotkeys_enabled", False):
            self._start_hotkeys()
        if self.config.get("auto_switch_enabled", False):
            self._start_auto_switch()
        self._register_wake_observer()
        self._start_wake_detector()

    # ── Menü aufbauen ─────────────────────────────────────────────

    def _rebuild_menu_safe(self):
        """Baut das Menü neu auf – garantiert auf dem Haupt-Thread.

        NSMenu darf nur vom Haupt-Thread aus geändert werden. Aufrufe aus
        Hintergrund-Threads (z. B. nach dem Speichern/Bearbeiten eines
        Profils) werden daher auf den Haupt-Thread umgeleitet, sonst
        erscheint das neue Profil nicht im Menü.
        """
        try:
            from PyObjCTools import AppHelper
            AppHelper.callAfter(self._build_menu)
        except Exception:
            self._build_menu()

    def _colorize_arrow(self, item, title):
        """Hebt den Eintrag des aktuell aktiven Profils farblich hervor.

        Der gesamte Titel wird blau eingefärbt, damit das aktive Profil auch
        neben einem Emoji deutlich erkennbar bleibt. Schlägt das Setzen des
        attribuierten Titels fehl (z. B. fehlende PyObjC-Symbole), bleibt der
        normale Titel erhalten.
        """
        try:
            attr = NSMutableAttributedString.alloc().initWithString_(title)
            attr.addAttribute_value_range_(
                NSForegroundColorAttributeName,
                NSColor.systemBlueColor(),
                NSMakeRange(0, attr.length()),
            )
            item._menuitem.setAttributedTitle_(attr)
        except Exception:
            pass

    def _build_menu(self):
        self.menu.clear()

        # Schnellauswahl: gespeicherte Profile direkt im Hauptmenü
        quick_profiles = list_profiles()
        hotkeys_on = self.config.get("hotkeys_enabled", False)
        hk_sym = self._hotkey_symbol()
        if quick_profiles:
            for i, p in enumerate(quick_profiles):
                is_active = (p["name"] == self._active_profile)
                # Tastenkürzel-Hinweis für die ersten 9 Profile
                suffix = ""
                if hotkeys_on and i < 9:
                    suffix = f"   {hk_sym}{i + 1}"
                emoji_prefix = (p.get("emoji") + " ") if p.get("emoji") else ""
                title = f"▶︎ {emoji_prefix}{p['name']}{suffix}"
                item = rumps.MenuItem(title, callback=self.on_restore)
                item._profile_name = p["name"]
                if is_active:
                    self._colorize_arrow(item, title)
                self.menu.add(item)
            self.menu.add(rumps.separator)

        # Alle Funktionen liegen im Untermenü "Einstellungen"
        settings_menu = rumps.MenuItem("⚙️ " + L("Einstellungen", "Settings"))

        # Speichern
        save_menu = rumps.MenuItem("💾 " + L("Desktop-Profile speichern …", "Save desktop profiles …"))
        save_new = rumps.MenuItem(L("Neues Profil …", "New profile …"), callback=self.on_save_new)
        save_menu.add(save_new)
        save_menu.add(rumps.separator)
        for p in list_profiles():
            item = rumps.MenuItem(
                L("Überschreiben: ", "Overwrite: ") + ((p.get("emoji") + " ") if p.get("emoji") else "") + p["name"],
                callback=self.on_save_existing
            )
            item._profile_name = p["name"]
            save_menu.add(item)
        settings_menu.add(save_menu)

        # Wiederherstellen
        restore_menu = rumps.MenuItem("🔄 " + L("Desktop-Profile wiederherstellen", "Restore desktop profiles"))
        profiles = list_profiles()
        if profiles:
            for p in profiles:
                prefix = (p.get("emoji") + " ") if p.get("emoji") else ""
                item = rumps.MenuItem(
                    f"{prefix}{p['name']}",
                    callback=self.on_restore
                )
                item._profile_name = p["name"]
                restore_menu.add(item)
        else:
            restore_menu.add(rumps.MenuItem(L("(keine Profile vorhanden)", "(no profiles available)")))
        settings_menu.add(restore_menu)

        settings_menu.add(rumps.separator)

        # Icons ein-/ausblenden (öffnet Fenster)
        visibility_item = rumps.MenuItem(
            "👁 " + L("Desktop-Icons ein-/ausblenden …", "Show/hide desktop icons …"),
            callback=self.on_open_visibility_window
        )
        settings_menu.add(visibility_item)

        # Apps für Profile auswählen (öffnet Fenster)
        app_select_item = rumps.MenuItem(
            "🚀 " + L("Apps für Profile auswählen …", "Select apps for profiles …"),
            callback=self.on_open_app_selection_window
        )
        settings_menu.add(app_select_item)

        settings_menu.add(rumps.separator)

        # Auto-Restore
        auto_item = rumps.MenuItem(
            "⏱ " + L("Auto-Wiederherstellen", "Auto restore"),
            callback=self.on_toggle_auto_restore
        )
        auto_item.state = self.config["auto_restore_enabled"]
        settings_menu.add(auto_item)

        # Intervall
        interval_menu = rumps.MenuItem("⏰ " + L("Intervall", "Interval"))
        current = self.config["auto_restore_interval_minutes"]
        for mins in INTERVAL_OPTIONS:
            if mins < 60:
                label = L(f"{mins} Minuten", f"{mins} minutes")
            else:
                hrs = mins // 60
                label = L(f"{hrs} Stunde{'n' if mins > 60 else ''}",
                          f"{hrs} hour{'s' if mins > 60 else ''}")
            item = rumps.MenuItem(label, callback=self.on_set_interval)
            item._interval_minutes = mins
            item.state = (mins == current)
            interval_menu.add(item)
        settings_menu.add(interval_menu)

        # Auto-Restore Profil
        profile_menu = rumps.MenuItem("📋 " + L("Auto-Restore-Profil", "Auto-restore profile"))
        current_profile = self.config["auto_restore_profile"]
        for p in list_profiles():
            item = rumps.MenuItem(p["name"], callback=self.on_set_auto_profile)
            item._profile_name = p["name"]
            item.state = (p["name"] == current_profile)
            profile_menu.add(item)
        if not profiles:
            profile_menu.add(rumps.MenuItem(L("(erst ein Profil speichern)", "(save a profile first)")))
        settings_menu.add(profile_menu)

        settings_menu.add(rumps.separator)

        # Profil bearbeiten
        edit_menu = rumps.MenuItem("✏️ " + L("Profil bearbeiten", "Edit profile"))
        for p in list_profiles():
            item = rumps.MenuItem(p["name"], callback=self.on_edit_profile)
            item._profile_name = p["name"]
            edit_menu.add(item)
        if not profiles:
            edit_menu.add(rumps.MenuItem(L("(keine Profile)", "(no profiles)")))
        settings_menu.add(edit_menu)

        # Profil löschen
        delete_menu = rumps.MenuItem("🗑 " + L("Profil löschen", "Delete profile"))
        for p in list_profiles():
            item = rumps.MenuItem(p["name"], callback=self.on_delete_profile)
            item._profile_name = p["name"]
            delete_menu.add(item)
        if not profiles:
            delete_menu.add(rumps.MenuItem(L("(keine Profile)", "(no profiles)")))
        settings_menu.add(delete_menu)

        # Profil exportieren (pro Profil)
        export_menu = rumps.MenuItem("📤 " + L("Profil exportieren", "Export profile"))
        for p in list_profiles():
            item = rumps.MenuItem(p["name"], callback=self.on_export_profile)
            item._profile_name = p["name"]
            export_menu.add(item)
        if not profiles:
            export_menu.add(rumps.MenuItem(L("(keine Profile)", "(no profiles)")))
        settings_menu.add(export_menu)

        # Profil importieren
        settings_menu.add(rumps.MenuItem(
            "📥 " + L("Profil importieren …", "Import profile …"),
            callback=self.on_import_profile))

        settings_menu.add(rumps.separator)

        # Beim Login wiederherstellen
        login_restore_item = rumps.MenuItem(
            "🔁 " + L("Beim Login Icons wiederherstellen", "Restore icons at login"),
            callback=self.on_toggle_restore_on_login
        )
        login_restore_item.state = self.config.get("restore_on_login", True)
        settings_menu.add(login_restore_item)

        # Nach Ruhemodus wiederherstellen
        wake_restore_item = rumps.MenuItem(
            "😴 " + L("Nach Ruhemodus wiederherstellen", "Restore after sleep"),
            callback=self.on_toggle_restore_on_wake
        )
        wake_restore_item.state = self.config.get("restore_on_wake", True)
        settings_menu.add(wake_restore_item)

        # Hintergrund mit wiederherstellen
        wallpaper_item = rumps.MenuItem(
            "🖼 " + L("Hintergrund mit wiederherstellen", "Restore wallpaper too"),
            callback=self.on_toggle_restore_wallpaper
        )
        wallpaper_item.state = self.config.get("restore_wallpaper", True)
        settings_menu.add(wallpaper_item)

        # Apps beim Wiederherstellen starten
        apps_item = rumps.MenuItem(
            "🚀 " + L("Apps beim Wiederherstellen starten", "Launch apps on restore"),
            callback=self.on_toggle_restore_apps
        )
        apps_item.state = self.config.get("restore_apps", True)
        settings_menu.add(apps_item)

        # Andere Apps beim Wechsel ausblenden
        hide_others_item = rumps.MenuItem(
            "🙈 " + L("Andere Apps beim Wechsel ausblenden", "Hide other apps when switching"),
            callback=self.on_toggle_hide_other_apps
        )
        hide_others_item.state = self.config.get("hide_other_apps", False)
        settings_menu.add(hide_others_item)

        # Andere Apps beim Wechsel beenden
        quit_others_item = rumps.MenuItem(
            "⛔ " + L("Andere Apps beim Wechsel beenden", "Quit other apps when switching"),
            callback=self.on_toggle_quit_other_apps
        )
        quit_others_item.state = self.config.get("quit_other_apps", False)
        settings_menu.add(quit_others_item)

        # App-Startverzögerung (Sekunden zwischen den App-Starts)
        delay_menu = rumps.MenuItem("⏳ " + L("App-Startverzögerung", "App launch delay"))
        current_delay = float(self.config.get("app_launch_delay", 1.5))
        for secs in (0, 0.5, 1, 1.5, 2, 3, 5):
            if secs == 0:
                label = L("Keine", "None")
            else:
                txt = str(int(secs)) if float(secs).is_integer() else str(secs)
                label = L(f"{txt} Sek.", f"{txt} sec")
            item = rumps.MenuItem(label, callback=self.on_set_launch_delay)
            item._delay_seconds = float(secs)
            item.state = (abs(float(secs) - current_delay) < 0.01)
            delay_menu.add(item)
        settings_menu.add(delay_menu)

        # Autostart
        autostart_item = rumps.MenuItem(
            "🚀 " + L("Beim Anmelden starten", "Start at login"),
            callback=self.on_toggle_autostart
        )
        autostart_item.state = is_autostart_enabled()
        settings_menu.add(autostart_item)

        # Globale Kurzbefehle
        sym = self._hotkey_symbol()
        hotkeys_item = rumps.MenuItem(
            "⌨️ " + L(f"Kurzbefehle {sym}1–9", f"Shortcuts {sym}1–9"),
            callback=self.on_toggle_hotkeys
        )
        hotkeys_item.state = self.config.get("hotkeys_enabled", False)
        settings_menu.add(hotkeys_item)

        # Tastenkombination wählen
        hk_mod_menu = rumps.MenuItem(
            "⌨️ " + L("Tastenkombination", "Key combination"))
        current_mod = self.config.get("hotkey_modifier", "cmd_ctrl")
        mod_labels = {
            "cmd_ctrl": L("⌘⌃ (Cmd+Ctrl)", "⌘⌃ (Cmd+Ctrl)"),
            "ctrl": L("⌃ (Ctrl/Strg)", "⌃ (Ctrl)"),
            "opt_cmd": L("⌥⌘ (Option+Cmd)", "⌥⌘ (Option+Cmd)"),
            "ctrl_shift": L("⌃⇧ (Ctrl+Shift)", "⌃⇧ (Ctrl+Shift)"),
        }
        for mkey in ("cmd_ctrl", "ctrl", "opt_cmd", "ctrl_shift"):
            mi = rumps.MenuItem(mod_labels[mkey] + L(" + 1–9", " + 1–9"),
                                callback=self.on_set_hotkey_modifier)
            mi._hotkey_modifier = mkey
            mi.state = (mkey == current_mod)
            hk_mod_menu.add(mi)
        settings_menu.add(hk_mod_menu)

        # Automatisches Umschalten (Zeit/WLAN)
        autoswitch_menu = rumps.MenuItem("🕓 " + L("Auto-Umschalten (Zeit/WLAN)",
                                                   "Auto switch (time/Wi-Fi)"))
        as_toggle = rumps.MenuItem(L("Aktiviert", "Enabled"),
                                   callback=self.on_toggle_auto_switch)
        as_toggle.state = self.config.get("auto_switch_enabled", False)
        autoswitch_menu.add(as_toggle)
        autoswitch_menu.add(rumps.separator)
        autoswitch_menu.add(rumps.MenuItem(
            "➕ " + L("Zeitregel hinzufügen … (Profil nach Uhrzeit)",
                      "Add time rule … (profile by time)"),
            callback=self.on_add_time_rule))
        # WLAN wird pro Profil im Profil-Dialog zugeordnet
        wifi_hint = rumps.MenuItem(
            "📶 " + L("WLAN: im Profil bearbeiten festlegen",
                      "Wi-Fi: set in 'Edit profile'"))
        wifi_hint.set_callback(None)
        autoswitch_menu.add(wifi_hint)
        # Aktuelle WLAN-Zuordnungen der Profile anzeigen
        wifi_assignments = [(p["name"], p["wifi_ssid"])
                            for p in list_profiles() if p.get("wifi_ssid")]
        if wifi_assignments:
            for pname, ssid in wifi_assignments:
                info = rumps.MenuItem(f"   📶 {ssid} → {pname}")
                info.set_callback(None)
                autoswitch_menu.add(info)
        # Zeitregeln auflisten (löschbar)
        rules = self.config.get("auto_switch_rules", [])
        time_rules = [(i, r) for i, r in enumerate(rules) if r.get("type") == "time"]
        legacy_wifi = [(i, r) for i, r in enumerate(rules) if r.get("type") == "wifi"]
        if time_rules or legacy_wifi:
            autoswitch_menu.add(rumps.separator)
            for i, rule in time_rules:
                desc = f"⏰ {rule.get('value')} → {rule.get('profile')}"
                item = rumps.MenuItem(desc + L("  (löschen)", "  (delete)"),
                                      callback=self.on_delete_auto_switch_rule)
                item._rule_index = i
                autoswitch_menu.add(item)
            for i, rule in legacy_wifi:
                desc = f"📶 {rule.get('value')} → {rule.get('profile')}"
                item = rumps.MenuItem(desc + L("  (löschen)", "  (delete)"),
                                      callback=self.on_delete_auto_switch_rule)
                item._rule_index = i
                autoswitch_menu.add(item)
        settings_menu.add(autoswitch_menu)

        settings_menu.add(rumps.separator)

        # Sprache
        lang_menu = rumps.MenuItem("🌐 " + L("Sprache", "Language"))
        current_lang = self.config.get("language", "system")
        for code, label in (
            ("system", L("System", "System")),
            ("de", L("Deutsch", "German")),
            ("en", L("Englisch", "English")),
        ):
            item = rumps.MenuItem(label, callback=self.on_set_language)
            item._lang_code = code
            item.state = (code == current_lang)
            lang_menu.add(item)
        settings_menu.add(lang_menu)

        # Nach Updates suchen (unterhalb der Sprachumschaltung)
        settings_menu.add(rumps.MenuItem(
            "⬆️ " + L("Nach Updates suchen …", "Check for updates …"),
            callback=self.on_check_update))

        settings_menu.add(rumps.separator)

        # Status
        if self.config["auto_restore_enabled"]:
            interval = self.config["auto_restore_interval_minutes"]
            profile = self.config["auto_restore_profile"]
            if interval < 60:
                iv_text = L(f"alle {interval} Min.", f"every {interval} min")
            else:
                iv_text = L(f"alle {interval // 60} Std.", f"every {interval // 60} h")
            status_text = L(f"Auto: '{profile}' {iv_text}", f"Auto: '{profile}' {iv_text}")
        else:
            status_text = L("Auto-Restore: Aus", "Auto restore: off")
        status = rumps.MenuItem(f"ℹ️ {status_text}")
        status.set_callback(None)
        settings_menu.add(status)

        # Untermenü ins Hauptmenü einhängen
        self.menu.add(settings_menu)

        self.menu.add(rumps.separator)
        self.menu.add(rumps.MenuItem(
            L("Hilfe – Profil erstellen", "Help – create a profile"), callback=self.on_help))
        self.menu.add(rumps.MenuItem(
            L("Über Desktop Profile Manager", "About Desktop Profile Manager"), callback=self.on_about))
        self.menu.add(rumps.MenuItem(L("Beenden", "Quit"), callback=self.on_quit))

    # ── Callbacks ─────────────────────────────────────────────────

    def on_save_new(self, _):
        self._open_profile_setup_window()

    def on_save_existing(self, sender):
        name = sender._profile_name
        # Beim Überschreiben die im Profil gespeicherten Einstellungen beibehalten
        settings = None
        included_apps = None
        try:
            path = get_profile_path(name)
            if path.exists():
                data = json.loads(path.read_text(encoding="utf-8"))
                saved = data.get("settings") or {}
                if saved:
                    settings = {
                        "capture_positions": saved.get("capture_positions", True),
                        "capture_hidden": saved.get("capture_hidden", True),
                        "capture_wallpaper": saved.get("capture_wallpaper", True),
                        "capture_apps": saved.get("capture_apps", True),
                    }
                    included_apps = saved.get("included_apps")
        except (json.JSONDecodeError, OSError, ValueError):
            pass
        self._do_save_with_settings(name, settings, included_apps)

    def _do_save_with_settings(self, name, settings=None, included_apps=None):
        """Speichert ein Profil mit den gewählten Einstellungen (im Hintergrund)."""
        if settings is None:
            settings = {}

        def task():
            try:
                kwargs = dict(
                    with_positions=settings.get("capture_positions", True),
                    with_hidden=settings.get("capture_hidden", True),
                    with_wallpaper=settings.get("capture_wallpaper", True),
                    with_apps=settings.get("capture_apps", True),
                    system_state_keys=settings.get("system_state_keys", []),
                    emoji=settings.get("emoji", ""),
                    wifi_ssid=settings.get("wifi_ssid", ""),
                )
                if included_apps is not None:
                    kwargs["included_apps"] = included_apps
                count, path = save_profile(
                    name, self.config.get("app_exclusions", []), **kwargs
                )
                if isinstance(path, Path):
                    parts = [f"{count} Icons"]
                    try:
                        data = json.loads(path.read_text(encoding="utf-8"))
                    except (json.JSONDecodeError, OSError):
                        data = {}
                    hidden = data.get("hidden", [])
                    if hidden:
                        parts.append(L(f"{len(hidden)} versteckt", f"{len(hidden)} hidden"))
                    apps = data.get("apps", [])
                    if apps:
                        parts.append(f"{len(apps)} Apps")
                    if data.get("wallpaper"):
                        parts.append(L("Hintergrund", "wallpaper"))
                    rumps.notification(
                        APP_NAME,
                        L(f"Profil '{name}' gespeichert", f"Profile '{name}' saved"),
                        ", ".join(parts) + L(" gesichert", " saved")
                    )
                else:
                    rumps.notification(APP_NAME, L("Fehler", "Error"), str(path))
            except Exception as e:
                rumps.notification(APP_NAME, L("Fehler beim Speichern", "Error while saving"), str(e))
            self._rebuild_menu_safe()
        threading.Thread(target=task, daemon=True).start()

    def on_edit_profile(self, sender):
        self._open_profile_setup_window(edit_name=sender._profile_name)

    def _apply_profile_edit(self, old_name, new_name, settings, included_apps):
        """Übernimmt Änderungen an einem bestehenden Profil.

        Anders als beim Neu-Speichern werden die bereits erfassten
        Icon-Positionen, versteckten Icons und das Hintergrundbild beibehalten.
        Geändert werden Name, die Wiederherstellungs-Optionen sowie die
        Auswahl der Apps (entfernte Apps fallen weg, neu hinzugefügte laufende
        Apps werden frisch erfasst).
        """
        def task():
            try:
                old_path = get_profile_path(old_name)
                if not old_path.exists():
                    rumps.notification(APP_NAME, L("Fehler", "Error"),
                                       L(f"Profil '{old_name}' nicht gefunden.",
                                         f"Profile '{old_name}' not found."))
                    return
                data = json.loads(old_path.read_text(encoding="utf-8"))

                # Optionen aktualisieren (capture_* und restore_* synchron halten)
                with_positions = settings.get("capture_positions", True)
                with_hidden = settings.get("capture_hidden", True)
                with_wallpaper = settings.get("capture_wallpaper", True)
                with_apps = settings.get("capture_apps", True)

                # App-Auswahl anwenden: bestehende Einträge behalten,
                # neu hinzugefügte laufende Apps frisch erfassen
                desired = list(dict.fromkeys(included_apps or []))
                existing_by_name = {a.get("name"): a for a in data.get("apps", [])}
                running_by_name = {a["name"]: a for a in capture_apps([])}
                new_apps = []
                for name in desired:
                    if name in existing_by_name:
                        new_apps.append(existing_by_name[name])
                    elif name in running_by_name:
                        new_apps.append(running_by_name[name])
                data["apps"] = new_apps

                # Systemzustand neu erfassen, falls Optionen gewählt
                sys_keys = list(settings.get("system_state_keys", []))
                data["system_state"] = capture_system_state(sys_keys)

                data["settings"] = {
                    "capture_positions": with_positions,
                    "capture_hidden": with_hidden,
                    "capture_wallpaper": with_wallpaper,
                    "capture_apps": with_apps,
                    "restore_positions": with_positions,
                    "restore_wallpaper": with_wallpaper,
                    "restore_apps": with_apps,
                    "included_apps": desired,
                    "system_state_keys": sys_keys,
                    "emoji": settings.get("emoji", ""),
                    "wifi_ssid": settings.get("wifi_ssid", ""),
                }
                data["profile"] = new_name
                data["saved_at"] = datetime.now().isoformat()

                new_path = get_profile_path(new_name)
                renamed = new_path != old_path
                if renamed and new_path.exists():
                    rumps.notification(
                        APP_NAME, L("Fehler", "Error"),
                        L(f"Ein Profil '{new_name}' existiert bereits.",
                          f"A profile '{new_name}' already exists.")
                    )
                    return

                _atomic_write_text(new_path, json.dumps(data, indent=2, ensure_ascii=False))
                if renamed:
                    try:
                        old_path.unlink()
                    except OSError:
                        pass
                    # Verweise in der Konfiguration mitziehen
                    if self.config.get("auto_restore_profile") == old_name:
                        self.config["auto_restore_profile"] = new_name
                        save_config(self.config)

                rumps.notification(
                    APP_NAME, L(f"Profil '{new_name}' aktualisiert",
                                f"Profile '{new_name}' updated"),
                    L(f"{len(new_apps)} Apps gespeichert", f"{len(new_apps)} apps saved")
                )
            except Exception as e:
                rumps.notification(APP_NAME, L("Fehler beim Bearbeiten", "Error while editing"), str(e))
            self._rebuild_menu_safe()
        threading.Thread(target=task, daemon=True).start()

    def _open_profile_setup_window(self, edit_name=None):
        """Öffnet das Setup-Fenster zum Anlegen oder Bearbeiten eines Profils.

        Im Neu-Modus (``edit_name is None``) werden Profilname und alle
        relevanten Einstellungen abgefragt und mit dem aktuellen Desktop-Zustand
        gespeichert. Im Bearbeiten-Modus werden Name, Optionen und App-Auswahl
        des bestehenden Profils vorausgefüllt; die bereits gespeicherten
        Icon-Positionen und das Hintergrundbild bleiben erhalten.
        """
        is_edit = edit_name is not None

        # Beim Bearbeiten die gespeicherten Werte laden
        saved_settings = {}
        saved_app_names = []
        if is_edit:
            try:
                data = json.loads(get_profile_path(edit_name).read_text(encoding="utf-8"))
                saved_settings = data.get("settings") or {}
                inc = saved_settings.get("included_apps")
                if inc is not None:
                    saved_app_names = list(inc)
                else:
                    saved_app_names = [a.get("name") for a in data.get("apps", [])
                                       if a.get("name")]
            except (json.JSONDecodeError, OSError, ValueError):
                rumps.notification(APP_NAME, L("Fehler", "Error"),
                                   L(f"Profil '{edit_name}' konnte nicht gelesen werden.",
                                     f"Profile '{edit_name}' could not be read."))
                return

        try:
            running = get_running_apps()
        except Exception:
            running = []
        running_names = [a["name"] for a in running]
        exclusions = set(self.config.get("app_exclusions", []))

        # App-Liste: beim Bearbeiten Union aus gespeicherten + laufenden Apps
        if is_edit:
            app_names = list(dict.fromkeys(saved_app_names + running_names))
            checked_names = set(saved_app_names)
        else:
            app_names = running_names
            checked_names = {n for n in running_names if n not in exclusions}

        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)

        padding = 16
        view_width = 460
        row_height = 26
        window_height = 760

        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(200, 200, view_width, window_height),
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered,
            False,
        )
        window.setTitle_(L("Profil bearbeiten", "Edit profile") if is_edit
                         else L("Neues Profil erstellen", "Create new profile"))
        window.setMinSize_((440, 640))
        content_view = window.contentView()
        inner_w = view_width - 2 * padding

        def label(text, y, height=18, size=12, bold=False):
            tf = NSTextField.alloc().initWithFrame_(
                NSMakeRect(padding, y, inner_w, height)
            )
            tf.setStringValue_(text)
            tf.setBezeled_(False)
            tf.setDrawsBackground_(False)
            tf.setEditable_(False)
            tf.setSelectable_(False)
            font = (NSFont.boldSystemFontOfSize_(size) if bold
                    else NSFont.systemFontOfSize_(size))
            tf.setFont_(font)
            content_view.addSubview_(tf)
            return tf

        # Layout-Cursor von oben nach unten
        y_cursor = window_height - 18

        def add_header(text):
            nonlocal y_cursor
            label(text, y_cursor - 18, bold=True)
            y_cursor -= 26

        def add_switch(text, on):
            nonlocal y_cursor
            cb = NSButton.alloc().initWithFrame_(
                NSMakeRect(padding, y_cursor - 22, inner_w, 22)
            )
            cb.setButtonType_(NSButtonTypeSwitch)
            cb.setTitle_(text)
            cb.setFont_(NSFont.systemFontOfSize_(13))
            cb.setState_(NSControlStateValueOn if on else NSControlStateValueOff)
            content_view.addSubview_(cb)
            y_cursor -= row_height
            return cb

        # Profilname
        label(L("Profilname:", "Profile name:"), y_cursor - 18, bold=True)
        y_cursor -= 24
        emoji_w = 56
        emoji_field = NSTextField.alloc().initWithFrame_(
            NSMakeRect(padding, y_cursor - 24, emoji_w, 24)
        )
        emoji_field.setPlaceholderString_("🙂")
        emoji_field.setFont_(NSFont.systemFontOfSize_(15))
        emoji_field.setAlignment_(2)  # center
        if is_edit:
            emoji_field.setStringValue_(saved_settings.get("emoji") or "")
        content_view.addSubview_(emoji_field)
        emoji_btn_w = 34
        emoji_btn = NSButton.alloc().initWithFrame_(
            NSMakeRect(padding + emoji_w + 6, y_cursor - 26, emoji_btn_w, 28)
        )
        emoji_btn.setTitle_("😀")
        emoji_btn.setBezelStyle_(NSBezelStyleRounded)
        emoji_btn.setFont_(NSFont.systemFontOfSize_(15))
        emoji_btn.setToolTip_(L("Emoji-Auswahl öffnen", "Open emoji picker"))
        content_view.addSubview_(emoji_btn)
        name_x = padding + emoji_w + 6 + emoji_btn_w + 8
        name_field = NSTextField.alloc().initWithFrame_(
            NSMakeRect(name_x, y_cursor - 24, padding + inner_w - name_x, 24)
        )
        name_field.setPlaceholderString_(L("z. B. Arbeit", "e.g. Work"))
        name_field.setFont_(NSFont.systemFontOfSize_(13))
        if is_edit:
            name_field.setStringValue_(edit_name)
        content_view.addSubview_(name_field)
        y_cursor -= 34

        # WLAN-Zuordnung (optional) für Auto-Umschalten
        label(L("Dieses Profil automatisch laden, wenn mit diesem WLAN verbunden:",
                "Load this profile automatically when connected to this Wi-Fi:"),
              y_cursor - 18, bold=True)
        y_cursor -= 24
        wifi_btn_w = 130
        wifi_field = NSTextField.alloc().initWithFrame_(
            NSMakeRect(padding, y_cursor - 24, inner_w - wifi_btn_w - 8, 24)
        )
        wifi_field.setPlaceholderString_(L("z. B. FRITZ!Box 7590", "e.g. MyNetwork"))
        wifi_field.setFont_(NSFont.systemFontOfSize_(13))
        if is_edit:
            wifi_field.setStringValue_(saved_settings.get("wifi_ssid") or "")
        content_view.addSubview_(wifi_field)
        wifi_btn = NSButton.alloc().initWithFrame_(
            NSMakeRect(padding + inner_w - wifi_btn_w, y_cursor - 26, wifi_btn_w, 28)
        )
        wifi_btn.setTitle_(L("Aktuelles WLAN", "Current Wi-Fi"))
        wifi_btn.setBezelStyle_(NSBezelStyleRounded)
        wifi_btn.setFont_(NSFont.systemFontOfSize_(11))
        content_view.addSubview_(wifi_btn)
        y_cursor -= 26
        hint = label(
            L("Leer lassen, wenn nicht gewünscht. 'Auto-Umschalten' muss aktiv sein.",
              "Leave empty if not needed. 'Auto switch' must be enabled."),
            y_cursor - 14, height=14, size=10)
        hint.setTextColor_(NSColor.secondaryLabelColor())
        y_cursor -= 22

        # Inhalt-Optionen
        if is_edit:
            add_header(L("Was soll wiederhergestellt werden?", "What should be restored?"))
        else:
            add_header(L("Was soll gespeichert werden?", "What should be saved?"))
        option_defs = [
            ("capture_positions", L("Icon-Positionen", "Icon positions")),
            ("capture_hidden", L("Versteckte Icons", "Hidden icons")),
            ("capture_wallpaper", L("Hintergrundbild", "Wallpaper")),
            ("capture_apps", L("Apps", "Apps")),
        ]
        options = {}
        for key, text in option_defs:
            default_on = saved_settings.get(key, True) if is_edit else True
            options[key] = add_switch(text, default_on)

        y_cursor -= 6

        # Systemzustand-Optionen (standardmäßig aus, da systemweit wirksam)
        add_header(L("Systemzustand (optional):", "System state (optional):"))
        saved_sys_keys = set(saved_settings.get("system_state_keys") or [])
        system_options = {}
        for key, opt in SYSTEM_STATE_OPTIONS.items():
            text = opt["label"][1] if CURRENT_LANG == "en" else opt["label"][0]
            on = key in saved_sys_keys if is_edit else False
            system_options[key] = add_switch(text, on)

        y_cursor -= 6

        # App-Liste
        add_header(L("Apps für dieses Profil:", "Apps for this profile:"))
        scroll_top = y_cursor
        scroll_bottom = 90
        scroll_height = max(scroll_top - scroll_bottom, 80)
        scroll_view = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(0, scroll_bottom, view_width, scroll_height)
        )
        scroll_view.setHasVerticalScroller_(True)
        scroll_view.setAutoresizingMask_(0b010010)

        content_height = max(len(app_names) * row_height, scroll_height)
        doc_view = NSView.alloc().initWithFrame_(
            NSMakeRect(0, 0, view_width - 20, content_height)
        )
        app_checkboxes = []
        for i, app_name in enumerate(app_names):
            y = content_height - (i + 1) * row_height
            cb = NSButton.alloc().initWithFrame_(
                NSMakeRect(padding, y, view_width - 2 * padding - 20, row_height)
            )
            cb.setButtonType_(NSButtonTypeSwitch)
            # Beim Bearbeiten kennzeichnen, welche Apps aktuell nicht laufen
            title = app_name
            if is_edit and app_name not in running_names:
                title = app_name + L("  (nicht aktiv)", "  (not running)")
            cb.setTitle_(title)
            cb.setFont_(NSFont.systemFontOfSize_(13))
            cb.setState_(NSControlStateValueOn if app_name in checked_names
                         else NSControlStateValueOff)
            cb.setTag_(i)
            doc_view.addSubview_(cb)
            app_checkboxes.append((app_name, cb))
        scroll_view.setDocumentView_(doc_view)
        content_view.addSubview_(scroll_view)

        # Button "Alle Apps auswählen"
        btn_all = NSButton.alloc().initWithFrame_(
            NSMakeRect(padding, 52, 170, 28)
        )
        btn_all.setTitle_(L("Alle Apps auswählen", "Select all apps"))
        btn_all.setBezelStyle_(NSBezelStyleRounded)

        # Buttons unten: Abbrechen / Speichern
        btn_create = NSButton.alloc().initWithFrame_(
            NSMakeRect(view_width - padding - 170, 16, 170, 28)
        )
        btn_create.setTitle_(L("Änderungen speichern", "Save changes") if is_edit
                             else L("Profil erstellen", "Create profile"))
        btn_create.setBezelStyle_(NSBezelStyleRounded)
        btn_create.setKeyEquivalent_("\r")

        btn_cancel = NSButton.alloc().initWithFrame_(
            NSMakeRect(view_width - padding - 170 - 8 - 110, 16, 110, 28)
        )
        btn_cancel.setTitle_(L("Abbrechen", "Cancel"))
        btn_cancel.setBezelStyle_(NSBezelStyleRounded)
        btn_cancel.setTarget_(window)
        btn_cancel.setAction_("performClose:")

        delegate = ProfileSetupWindowDelegate.alloc().initWithFields_window_app_(
            {
                "name_field": name_field,
                "emoji_field": emoji_field,
                "wifi_field": wifi_field,
                "options": options,
                "system_options": system_options,
                "app_checkboxes": app_checkboxes,
                "edit_name": edit_name,
            },
            window,
            self,
        )
        btn_all.setTarget_(delegate)
        btn_all.setAction_(objc.selector(delegate.onSelectAllApps_, signature=b"v@:@"))
        btn_create.setTarget_(delegate)
        btn_create.setAction_(objc.selector(delegate.onCreate_, signature=b"v@:@"))

        content_view.addSubview_(btn_all)
        content_view.addSubview_(btn_create)
        content_view.addSubview_(btn_cancel)

        wifi_btn.setTarget_(delegate)
        wifi_btn.setAction_(objc.selector(delegate.onUseCurrentWifi_, signature=b"v@:@"))

        emoji_btn.setTarget_(delegate)
        emoji_btn.setAction_(objc.selector(delegate.onPickEmoji_, signature=b"v@:@"))

        self._setup_window = window
        self._setup_delegate = delegate
        window.setDelegate_(delegate)
        window.setReleasedWhenClosed_(False)
        window.makeFirstResponder_(name_field)

        window.center()
        window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)

    def on_restore(self, sender):
        name = sender._profile_name
        self._do_restore(name, notify=True, mark_active=True)

    def _do_restore(self, name, notify=True, include_apps=None, mark_active=False):
        if include_apps is None:
            include_apps = self.config.get("restore_apps", True)
        include_wallpaper = self.config.get("restore_wallpaper", True)
        hide_others = self.config.get("hide_other_apps", False)
        quit_others = self.config.get("quit_other_apps", False)
        launch_delay = float(self.config.get("app_launch_delay", 1.5))

        def task():
            try:
                success, failed, error, warning = restore_profile(
                    name, include_wallpaper, include_apps, hide_others, quit_others,
                    launch_delay
                )
                if error:
                    if notify:
                        rumps.notification(APP_NAME, L("Fehler", "Error"), error)
                    return
                if mark_active:
                    self._active_profile = name
                    self._rebuild_menu_safe()
                msg = L(f"{success} Icons wiederhergestellt", f"{success} icons restored")
                if failed:
                    msg += L(f", {failed} fehlgeschlagen", f", {failed} failed")
                if warning:
                    msg += "\n⚠️ " + warning
                if notify:
                    rumps.notification(APP_NAME, L(f"Profil '{name}'", f"Profile '{name}'"), msg)
            except Exception as e:
                if notify:
                    rumps.notification(APP_NAME, L("Fehler", "Error"), str(e))
        threading.Thread(target=task, daemon=True).start()

    def on_toggle_auto_restore(self, sender):
        self.config["auto_restore_enabled"] = not self.config["auto_restore_enabled"]
        save_config(self.config)
        if self.config["auto_restore_enabled"]:
            self._start_auto_restore()
            rumps.notification(APP_NAME, L("Auto-Restore aktiviert", "Auto restore enabled"),
                               L(f"Profil '{self.config['auto_restore_profile']}' "
                                 f"wird alle {self.config['auto_restore_interval_minutes']} Min. wiederhergestellt.",
                                 f"Profile '{self.config['auto_restore_profile']}' "
                                 f"will be restored every {self.config['auto_restore_interval_minutes']} min."))
        else:
            self._stop_auto_restore()
            rumps.notification(APP_NAME, L("Auto-Restore deaktiviert", "Auto restore disabled"), "")
        self._build_menu()

    def on_open_visibility_window(self, _):
        """Öffnet ein Fenster mit Checkboxen für alle Desktop-Icons."""
        try:
            desktop_items = get_all_desktop_items()
        except Exception:
            rumps.notification(APP_NAME, L("Fehler", "Error"),
                               L("Desktop-Items konnten nicht gelesen werden.",
                                 "Desktop items could not be read."))
            return

        if not desktop_items:
            rumps.notification(APP_NAME, L("Keine Items", "No items"),
                               L("Keine Icons auf dem Desktop gefunden.",
                                 "No icons found on the desktop."))
            return

        # App temporär sichtbar machen für das Fenster
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)

        row_height = 26
        padding = 16
        content_height = len(desktop_items) * row_height
        window_height = min(content_height + 120, 600)

        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(200, 200, 420, window_height),
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered,
            False,
        )
        window.setTitle_(L("Icons ein-/ausblenden", "Show/hide icons"))
        window.setMinSize_((350, 250))

        content_view = window.contentView()
        view_width = 420

        # Scrollbare Liste mit Checkboxen
        scroll_view = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(0, 50, view_width, window_height - 80)
        )
        scroll_view.setHasVerticalScroller_(True)
        scroll_view.setAutoresizingMask_(0b010010)  # Breite + Höhe flexibel

        doc_view = NSView.alloc().initWithFrame_(
            NSMakeRect(0, 0, view_width - 20, max(content_height, window_height - 80))
        )

        checkboxes = []
        for i, di in enumerate(desktop_items):
            y = content_height - (i + 1) * row_height
            cb = NSButton.alloc().initWithFrame_(
                NSMakeRect(padding, y, view_width - 2 * padding, row_height)
            )
            cb.setButtonType_(NSButtonTypeSwitch)
            cb.setTitle_(di["name"])
            cb.setFont_(NSFont.systemFontOfSize_(13))
            cb.setState_(NSControlStateValueOff if di["hidden"] else NSControlStateValueOn)
            cb.setTag_(i)
            doc_view.addSubview_(cb)
            checkboxes.append((di["name"], cb))

        scroll_view.setDocumentView_(doc_view)
        content_view.addSubview_(scroll_view)

        # Buttons unten
        btn_all = NSButton.alloc().initWithFrame_(
            NSMakeRect(padding, 12, 120, 28)
        )
        btn_all.setTitle_(L("Alle einblenden", "Show all"))
        btn_all.setBezelStyle_(NSBezelStyleRounded)

        btn_apply = NSButton.alloc().initWithFrame_(
            NSMakeRect(view_width - padding - 120, 12, 120, 28)
        )
        btn_apply.setTitle_(L("Anwenden", "Apply"))
        btn_apply.setBezelStyle_(NSBezelStyleRounded)
        btn_apply.setKeyEquivalent_("\r")  # Enter

        # Delegate für Button-Aktionen
        delegate = VisibilityWindowDelegate.alloc().initWithCheckboxes_window_app_(
            checkboxes, window, self
        )
        btn_all.setTarget_(delegate)
        btn_all.setAction_(objc.selector(delegate.onSelectAll_, signature=b"v@:@"))
        btn_apply.setTarget_(delegate)
        btn_apply.setAction_(objc.selector(delegate.onApply_, signature=b"v@:@"))

        content_view.addSubview_(btn_all)
        content_view.addSubview_(btn_apply)

        # Fenster und Delegate auf self speichern damit GC sie nicht freigibt
        self._visibility_window = window
        self._visibility_delegate = delegate
        window.setDelegate_(delegate)
        window.setReleasedWhenClosed_(False)

        window.center()
        window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)

    def on_open_app_selection_window(self, _):
        """Öffnet ein Fenster zur Auswahl der Apps, die in Profile aufgenommen werden."""
        try:
            apps = get_running_apps()
        except Exception:
            rumps.notification(APP_NAME, L("Fehler", "Error"),
                               L("Laufende Apps konnten nicht gelesen werden.",
                                 "Running apps could not be read."))
            return

        if not apps:
            rumps.notification(APP_NAME, L("Keine Apps", "No apps"),
                               L("Keine laufenden Apps gefunden.", "No running apps found."))
            return

        exclusions = set(self.config.get("app_exclusions", []))

        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)

        row_height = 26
        padding = 16
        view_width = 420
        content_height = len(apps) * row_height
        window_height = min(content_height + 140, 600)

        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(200, 200, view_width, window_height),
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered,
            False,
        )
        window.setTitle_(L("Apps für Profile auswählen", "Select apps for profiles"))
        window.setMinSize_((350, 250))

        content_view = window.contentView()

        # Hinweistext
        info = NSTextField.alloc().initWithFrame_(
            NSMakeRect(padding, window_height - 40, view_width - 2 * padding, 28)
        )
        info.setStringValue_(L("Angehakte Apps werden beim Speichern in Profile aufgenommen.",
                               "Checked apps will be included in profiles when saving."))
        info.setBezeled_(False)
        info.setDrawsBackground_(False)
        info.setEditable_(False)
        info.setSelectable_(False)
        info.setFont_(NSFont.systemFontOfSize_(12))
        content_view.addSubview_(info)

        scroll_view = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(0, 50, view_width, window_height - 90)
        )
        scroll_view.setHasVerticalScroller_(True)
        scroll_view.setAutoresizingMask_(0b010010)

        doc_view = NSView.alloc().initWithFrame_(
            NSMakeRect(0, 0, view_width - 20, max(content_height, window_height - 90))
        )

        checkboxes = []
        for i, app in enumerate(apps):
            y = content_height - (i + 1) * row_height
            cb = NSButton.alloc().initWithFrame_(
                NSMakeRect(padding, y, view_width - 2 * padding, row_height)
            )
            cb.setButtonType_(NSButtonTypeSwitch)
            cb.setTitle_(app["name"])
            cb.setFont_(NSFont.systemFontOfSize_(13))
            cb.setState_(NSControlStateValueOff if app["name"] in exclusions else NSControlStateValueOn)
            cb.setTag_(i)
            doc_view.addSubview_(cb)
            checkboxes.append((app["name"], cb))

        scroll_view.setDocumentView_(doc_view)
        content_view.addSubview_(scroll_view)

        btn_all = NSButton.alloc().initWithFrame_(
            NSMakeRect(padding, 12, 120, 28)
        )
        btn_all.setTitle_(L("Alle auswählen", "Select all"))
        btn_all.setBezelStyle_(NSBezelStyleRounded)

        btn_apply = NSButton.alloc().initWithFrame_(
            NSMakeRect(view_width - padding - 120, 12, 120, 28)
        )
        btn_apply.setTitle_(L("Speichern", "Save"))
        btn_apply.setBezelStyle_(NSBezelStyleRounded)
        btn_apply.setKeyEquivalent_("\r")

        delegate = AppSelectionWindowDelegate.alloc().initWithCheckboxes_window_app_(
            checkboxes, window, self
        )
        btn_all.setTarget_(delegate)
        btn_all.setAction_(objc.selector(delegate.onSelectAll_, signature=b"v@:@"))
        btn_apply.setTarget_(delegate)
        btn_apply.setAction_(objc.selector(delegate.onApply_, signature=b"v@:@"))

        content_view.addSubview_(btn_all)
        content_view.addSubview_(btn_apply)

        self._app_window = window
        self._app_delegate = delegate
        window.setDelegate_(delegate)
        window.setReleasedWhenClosed_(False)

        window.center()
        window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)

    def on_set_interval(self, sender):
        self.config["auto_restore_interval_minutes"] = sender._interval_minutes
        save_config(self.config)
        if self.config["auto_restore_enabled"]:
            self._stop_auto_restore()
            self._start_auto_restore()
        self._build_menu()

    def on_set_auto_profile(self, sender):
        self.config["auto_restore_profile"] = sender._profile_name
        save_config(self.config)
        self._build_menu()

    def on_set_launch_delay(self, sender):
        self.config["app_launch_delay"] = float(sender._delay_seconds)
        save_config(self.config)
        self._build_menu()

    def on_delete_profile(self, sender):
        name = sender._profile_name
        try:
            path = get_profile_path(name)
            if path.exists():
                path.unlink()
                rumps.notification(APP_NAME, L(f"Profil '{name}' gelöscht",
                                               f"Profile '{name}' deleted"), "")
        except Exception as e:
            rumps.notification(APP_NAME, L("Fehler", "Error"), str(e))
        self._build_menu()

    def on_export_profile(self, sender):
        """Exportiert ein Profil als JSON-Datei (Speichern-Dialog)."""
        name = sender._profile_name
        src = get_profile_path(name)
        if not src.exists():
            rumps.notification(APP_NAME, L("Fehler", "Error"),
                               L(f"Profil '{name}' nicht gefunden.",
                                 f"Profile '{name}' not found."))
            return
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)
        NSApp.activateIgnoringOtherApps_(True)
        try:
            panel = NSSavePanel.savePanel()
            panel.setTitle_(L("Profil exportieren", "Export profile"))
            panel.setNameFieldStringValue_(f"{name}.json")
            panel.setAllowedFileTypes_(["json"])
            result = panel.runModal()
            if result == 1:  # NSModalResponseOK
                dest = panel.URL().path()
                shutil.copyfile(str(src), dest)
                rumps.notification(
                    APP_NAME, L("Profil exportiert", "Profile exported"),
                    L(f"'{name}' wurde gespeichert.", f"'{name}' was saved."))
        except Exception as e:
            rumps.notification(APP_NAME, L("Fehler", "Error"), str(e))
        finally:
            NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    def on_import_profile(self, _):
        """Importiert ein Profil aus einer JSON-Datei (Öffnen-Dialog)."""
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)
        NSApp.activateIgnoringOtherApps_(True)
        try:
            panel = NSOpenPanel.openPanel()
            panel.setTitle_(L("Profil importieren", "Import profile"))
            panel.setAllowsMultipleSelection_(False)
            panel.setCanChooseDirectories_(False)
            panel.setAllowedFileTypes_(["json"])
            result = panel.runModal()
            if result != 1:  # nicht OK
                return
            src_path = panel.URL().path()
            try:
                data = json.loads(Path(src_path).read_text(encoding="utf-8"))
            except (json.JSONDecodeError, ValueError, OSError):
                rumps.notification(APP_NAME, L("Fehler", "Error"),
                                   L("Datei ist kein gültiges Profil.",
                                     "File is not a valid profile."))
                return
            if not isinstance(data, dict) or "positions" not in data:
                rumps.notification(APP_NAME, L("Fehler", "Error"),
                                   L("Datei ist kein gültiges Profil.",
                                     "File is not a valid profile."))
                return

            # Namen bestimmen (bei Konflikt durchnummerieren)
            base = data.get("profile") or Path(src_path).stem
            name = base
            counter = 2
            while get_profile_path(name).exists():
                name = f"{base} ({counter})"
                counter += 1
            data["profile"] = name

            PROFILES_DIR.mkdir(exist_ok=True)
            _atomic_write_text(
                get_profile_path(name),
                json.dumps(data, indent=2, ensure_ascii=False))
            rumps.notification(
                APP_NAME, L("Profil importiert", "Profile imported"),
                L(f"'{name}' wurde hinzugefügt.", f"'{name}' was added."))
            self._build_menu()
        except Exception as e:
            rumps.notification(APP_NAME, L("Fehler", "Error"), str(e))
        finally:
            NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    def on_toggle_restore_on_login(self, sender):
        self.config["restore_on_login"] = not self.config.get("restore_on_login", True)
        save_config(self.config)
        state = self.config["restore_on_login"]
        rumps.notification(
            APP_NAME,
            L("Login-Restore aktiviert", "Login restore enabled") if state
            else L("Login-Restore deaktiviert", "Login restore disabled"),
            L("Icons werden beim nächsten Login automatisch wiederhergestellt.",
              "Icons will be restored automatically at next login.")
            if state else L("Icons werden beim Login nicht mehr automatisch wiederhergestellt.",
                            "Icons will no longer be restored automatically at login.")
        )
        self._build_menu()

    def on_toggle_restore_on_wake(self, sender):
        self.config["restore_on_wake"] = not self.config.get("restore_on_wake", True)
        save_config(self.config)
        state = self.config["restore_on_wake"]
        rumps.notification(
            APP_NAME,
            L("Ruhemodus-Restore aktiviert", "Sleep restore enabled") if state
            else L("Ruhemodus-Restore deaktiviert", "Sleep restore disabled"),
            L("Icons werden nach dem Aufwachen automatisch wiederhergestellt.",
              "Icons will be restored automatically after wake.")
            if state else L("Icons werden nach dem Aufwachen nicht mehr wiederhergestellt.",
                            "Icons will no longer be restored after wake.")
        )
        self._build_menu()

    def on_toggle_restore_wallpaper(self, sender):
        self.config["restore_wallpaper"] = not self.config.get("restore_wallpaper", True)
        save_config(self.config)
        state = self.config["restore_wallpaper"]
        rumps.notification(
            APP_NAME,
            L("Hintergrund-Restore aktiviert", "Wallpaper restore enabled") if state
            else L("Hintergrund-Restore deaktiviert", "Wallpaper restore disabled"),
            L("Der gespeicherte Desktop-Hintergrund wird mit wiederhergestellt.",
              "The saved desktop wallpaper will be restored too.")
            if state else L("Der Desktop-Hintergrund wird nicht mehr verändert.",
                            "The desktop wallpaper will no longer be changed.")
        )
        self._build_menu()

    def on_toggle_restore_apps(self, sender):
        self.config["restore_apps"] = not self.config.get("restore_apps", True)
        save_config(self.config)
        state = self.config["restore_apps"]
        rumps.notification(
            APP_NAME,
            L("App-Start aktiviert", "App launch enabled") if state
            else L("App-Start deaktiviert", "App launch disabled"),
            L("Gespeicherte Apps werden beim Wiederherstellen gestartet.",
              "Saved apps will be launched on restore.")
            if state else L("Beim Wiederherstellen werden keine Apps gestartet.",
                            "No apps will be launched on restore.")
        )
        self._build_menu()

    def on_toggle_hide_other_apps(self, sender):
        self.config["hide_other_apps"] = not self.config.get("hide_other_apps", False)
        save_config(self.config)
        state = self.config["hide_other_apps"]
        if state:
            self.config["quit_other_apps"] = False
            save_config(self.config)
        rumps.notification(
            APP_NAME,
            L("Ausblenden aktiviert", "Hiding enabled") if state
            else L("Ausblenden deaktiviert", "Hiding disabled"),
            L("Apps, die nicht zum Profil gehören, werden beim Wechsel ausgeblendet.",
              "Apps that don't belong to the profile are hidden when switching.")
            if state else L("Andere Apps bleiben beim Wechsel sichtbar.",
                            "Other apps stay visible when switching.")
        )
        self._build_menu()

    def on_toggle_quit_other_apps(self, sender):
        will_enable = not self.config.get("quit_other_apps", False)
        if will_enable:
            # Warnung: Beenden kann zu Datenverlust führen.
            resp = rumps.alert(
                title=L("Achtung: Datenverlust möglich",
                        "Warning: possible data loss"),
                message=L(
                    "Wenn andere Apps beim Profilwechsel beendet werden, gehen "
                    "ungespeicherte Inhalte (z. B. offene Texte oder Dokumente) "
                    "in diesen Apps verloren.\n\n"
                    "Möchtest du diese Option wirklich aktivieren?",
                    "If other apps are quit when switching profiles, any unsaved "
                    "content (e.g. open texts or documents) in those apps will be "
                    "lost.\n\n"
                    "Do you really want to enable this option?"),
                ok=L("Aktivieren", "Enable"),
                cancel=L("Abbrechen", "Cancel"))
            if resp != 1:
                # Abgebrochen: Zustand unverändert lassen.
                self._build_menu()
                return
        self.config["quit_other_apps"] = will_enable
        save_config(self.config)
        state = self.config["quit_other_apps"]
        if state:
            # Beenden und Ausblenden schließen sich gegenseitig aus
            self.config["hide_other_apps"] = False
            save_config(self.config)
        rumps.notification(
            APP_NAME,
            L("Beenden aktiviert", "Quitting enabled") if state
            else L("Beenden deaktiviert", "Quitting disabled"),
            L("Apps, die nicht zum Profil gehören, werden beim Wechsel beendet.",
              "Apps that don't belong to the profile are quit when switching.")
            if state else L("Andere Apps werden beim Wechsel nicht mehr beendet.",
                            "Other apps will no longer be quit when switching.")
        )
        self._build_menu()

    def on_toggle_autostart(self, sender):
        if is_autostart_enabled():
            disable_autostart()
            rumps.notification(APP_NAME,
                               L("Autostart deaktiviert", "Autostart disabled"),
                               L("App wird nicht mehr beim Anmelden gestartet.",
                                 "The app will no longer start at login."))
        else:
            enable_autostart()
            rumps.notification(APP_NAME,
                               L("Autostart aktiviert", "Autostart enabled"),
                               L("App startet beim nächsten Anmelden automatisch.",
                                 "The app will start automatically at next login."))
        self._build_menu()

    def on_set_language(self, sender):
        self.config["language"] = sender._lang_code
        save_config(self.config)
        resolve_language(self.config)
        self._build_menu()
        rumps.notification(
            APP_NAME,
            L("Sprache geändert", "Language changed"),
            L("Die Sprache wurde aktualisiert.", "The language has been updated."),
        )

    def on_help(self, _):
        rumps.alert(
            title=L("Profil erstellen – Schritt für Schritt",
                    "Create a profile – step by step"),
            message=L(
                (
                    "So legst du ein neues Profil an:\n\n"
                    "1. Desktop vorbereiten:\n"
                    "   • Icons an die gewünschten Positionen ziehen\n"
                    "   • Gewünschten Hintergrund einstellen\n"
                    "   • Apps öffnen, die zum Profil gehören sollen\n"
                    "   • Über „👁 Icons ein-/ausblenden …“ Icons\n"
                    "     ausblenden, die versteckt sein sollen\n\n"
                    "2. Einstellungen ▸ „💾 Desktop-Profile speichern …“\n"
                    "   ▸ „Neues Profil …“ öffnen.\n\n"
                    "3. Im Setup-Fenster der Reihe nach:\n"
                    "   • Profilnamen eingeben (z. B. „Arbeit“)\n"
                    "   • Anhaken, was gespeichert wird: Icon-Positionen,\n"
                    "     versteckte Icons, Hintergrundbild, Apps\n"
                    "   • In der App-Liste die gewünschten Apps anhaken\n"
                    "   • „Profil erstellen“ klicken\n\n"
                    "4. Wiederherstellen:\n"
                    "   Im Hauptmenü oben auf „▶︎ <Profilname>“ klicken.\n\n"
                    "Bearbeiten / Löschen:\n"
                    "   Einstellungen ▸ „✏️ Profil bearbeiten“ bzw.\n"
                    "   „🗑 Profil löschen“.\n\n"
                    "Hinweise zu einzelnen Funktionen:\n"
                    "   • ⌨️ Kurzbefehle (⌘⌃1–9) benötigen die\n"
                    "     Bedienungshilfen-Berechtigung (die du für die\n"
                    "     Fensterpositionierung ohnehin schon erteilt hast).\n"
                    "   • 📶 WLAN-Erkennung: macOS schränkt das Auslesen der\n"
                    "     SSID je nach Version ein – die App probiert mehrere\n"
                    "     Wege; falls leer, SSID bitte manuell eintippen.\n"
                    "   • 🔆 Helligkeit benötigt das CLI-Tool\n"
                    "     (Terminal: „brew install brightness“).\n"
                    "   • 🌙 Fokus / Nicht stören funktioniert am\n"
                    "     zuverlässigsten über einen Kurzbefehl namens\n"
                    "     „Fokus ein“ / „Fokus aus“.\n\n"
                    "Tipp: Für Apps und Fensterpositionen muss die App unter\n"
                    "„Datenschutz & Sicherheit › Bedienungshilfen“ erlaubt sein."
                ),
                (
                    "How to create a new profile:\n\n"
                    "1. Prepare the desktop:\n"
                    "   • Drag icons to the positions you want\n"
                    "   • Set the wallpaper you want\n"
                    "   • Open the apps that should belong to the profile\n"
                    "   • Use “👁 Show/hide icons …” to hide the\n"
                    "     icons that should be hidden\n\n"
                    "2. Open Settings ▸ “💾 Save desktop profiles …”\n"
                    "   ▸ “New profile …”.\n\n"
                    "3. In the setup window, step by step:\n"
                    "   • Enter a profile name (e.g. “Work”)\n"
                    "   • Tick what gets saved: icon positions,\n"
                    "     hidden icons, wallpaper, apps\n"
                    "   • Tick the apps you want in the app list\n"
                    "   • Click “Create profile”\n\n"
                    "4. Restore:\n"
                    "   Click “▶︎ <profile name>” at the top of the main menu.\n\n"
                    "Edit / delete:\n"
                    "   Settings ▸ “✏️ Edit profile” or\n"
                    "   “🗑 Delete profile”.\n\n"
                    "Notes on specific features:\n"
                    "   • ⌨️ Shortcuts (⌘⌃1–9) require the Accessibility\n"
                    "     permission (which you already granted for window\n"
                    "     positioning).\n"
                    "   • 📶 Wi-Fi detection: macOS restricts reading the\n"
                    "     SSID depending on the version – the app tries\n"
                    "     several methods; if empty, please type the SSID\n"
                    "     manually.\n"
                    "   • 🔆 Brightness requires the CLI tool\n"
                    "     (Terminal: “brew install brightness”).\n"
                    "   • 🌙 Focus / Do Not Disturb works most reliably via\n"
                    "     a Shortcut named “Fokus ein” / “Fokus aus”.\n\n"
                    "Tip: For apps and window positions, the app must be allowed\n"
                    "under “Privacy & Security › Accessibility”."
                ),
            ),
            ok="OK"
        )

    def on_about(self, _):
        rumps.alert(
            title=L("Über Desktop Profile Manager", "About Desktop Profile Manager"),
            message=L(
                (
                    f"Desktop Profile Manager v{APP_VERSION}\n\n"
                    "Arbeitsumgebungs-Manager für macOS:\n"
                    "• Desktop-Icon-Positionen speichern/wiederherstellen\n"
                    "• Icons einzeln verstecken\n"
                    "• Desktop-Hintergrund pro Profil\n"
                    "• Apps inkl. Fensterposition/-größe starten\n\n"
                    "Hinweis: Für Fensterposition/-größe muss die App\n"
                    "in den Systemeinstellungen unter „Datenschutz &\n"
                    "Sicherheit › Bedienungshilfen“ erlaubt sein.\n\n"
                    "Copyright © 2026 Norbert Jander\n"
                    "Erstellt nach einer Idee von Norbert Jander.\n"
                    "Technische Umsetzung mit Claude Opus.\n\n"
                    "Lizenz: MIT"
                ),
                (
                    f"Desktop Profile Manager v{APP_VERSION}\n\n"
                    "Work environment manager for macOS:\n"
                    "• Save/restore desktop icon positions\n"
                    "• Hide individual icons\n"
                    "• Desktop wallpaper per profile\n"
                    "• Launch apps incl. window position/size\n\n"
                    "Note: For window position/size, the app must be\n"
                    "allowed in System Settings under “Privacy &\n"
                    "Security › Accessibility”.\n\n"
                    "Copyright © 2026 Norbert Jander\n"
                    "Based on an idea by Norbert Jander.\n"
                    "Technical implementation with Claude Opus.\n\n"
                    "License: MIT"
                ),
            ),
            ok="OK"
        )

    # ── Migration: alter IconGuard-Autostart ──────────────────────

    def _migrate_old_iconguard(self):
        """Stellt einen alten IconGuard-Autostart auf diese App um.

        Der Vorgänger „IconGuard" trug sich als Anmeldeobjekt (Login-Item)
        ein, das die alte ``/Applications/IconGuard.app`` startete. Diese
        einmalige Migration entfernt das alte Login-Item (und einen evtl.
        vorhandenen alten LaunchAgent) und aktiviert – damit der Autostart
        erhalten bleibt – den Autostart von Desktop Profile Manager.
        """
        if self.config.get("migrated_iconguard", False):
            return
        try:
            agents_dir = Path.home() / "Library" / "LaunchAgents"
            had_old_agent = any(
                (agents_dir / f"{label}.plist").exists()
                for label in OLD_LAUNCH_AGENT_LABELS
            )
            removed_login = _remove_old_login_item()
            if removed_login or had_old_agent:
                was_autostart = is_autostart_enabled() or had_old_agent
                _cleanup_old_autostart()
                if was_autostart and not is_autostart_enabled():
                    enable_autostart()
                rumps.notification(
                    APP_NAME,
                    L("Autostart übernommen", "Autostart migrated"),
                    L("Alte Autostart-Reste wurden entfernt und durch "
                      "Desktop Profile Manager ersetzt.",
                      "Old autostart leftovers were removed and replaced "
                      "by Desktop Profile Manager."))
        finally:
            self.config["migrated_iconguard"] = True
            save_config(self.config)

    # ── Update-Prüfung (GitHub-Releases) ──────────────────────────

    @staticmethod
    def _version_tuple(version: str):
        """Wandelt z. B. ``"1.2.0"`` in ``(1, 2, 0)`` für den Vergleich um."""
        parts = []
        for chunk in str(version).strip().lstrip("vV").split("."):
            num = "".join(ch for ch in chunk if ch.isdigit())
            parts.append(int(num) if num else 0)
        return tuple(parts)

    @classmethod
    def _version_gt(cls, a: str, b: str) -> bool:
        """``True``, wenn Version ``a`` neuer ist als Version ``b``."""
        ta, tb = cls._version_tuple(a), cls._version_tuple(b)
        length = max(len(ta), len(tb))
        ta += (0,) * (length - len(ta))
        tb += (0,) * (length - len(tb))
        return ta > tb

    def on_check_update(self, _):
        """Prüft im Hintergrund, ob ein neueres Release verfügbar ist."""
        threading.Thread(target=self._check_update_worker, daemon=True).start()

    def _check_update_worker(self):
        from PyObjCTools import AppHelper
        try:
            out = subprocess.run(
                ["/usr/bin/curl", "-sSL", "--max-time", "15",
                 "-H", "Accept: application/vnd.github+json",
                 "-H", "User-Agent: DesktopProfileManager",
                 GITHUB_RELEASES_API],
                capture_output=True, timeout=20,
            )
            if out.returncode != 0 or not out.stdout.strip():
                AppHelper.callAfter(self._update_failed)
                return
            data = json.loads(out.stdout.decode("utf-8", "replace"))
        except Exception:
            AppHelper.callAfter(self._update_failed)
            return

        latest = str(data.get("tag_name") or "").strip().lstrip("vV")
        if not latest:
            AppHelper.callAfter(self._update_failed)
            return
        asset_url = ""
        for asset in (data.get("assets") or []):
            url = asset.get("browser_download_url") or ""
            if url.lower().endswith(".dmg"):
                asset_url = url
                break
        available = self._version_gt(latest, APP_VERSION)
        AppHelper.callAfter(self._update_result, latest, asset_url, available)

    def _update_failed(self):
        rumps.alert(
            title=L("Update-Prüfung fehlgeschlagen", "Update check failed"),
            message=L(
                "Die Update-Informationen konnten nicht abgerufen werden.\n"
                "Bitte später erneut versuchen oder die Releases-Seite öffnen.",
                "Could not fetch update information.\n"
                "Please try again later or open the releases page."),
            ok="OK")

    def _update_result(self, latest, asset_url, available):
        if not available:
            rumps.alert(
                title=L("Keine Updates", "No updates"),
                message=L(
                    f"Du verwendest bereits die neueste Version (v{APP_VERSION}).",
                    f"You are already using the latest version (v{APP_VERSION})."),
                ok="OK")
            return
        if asset_url:
            resp = rumps.alert(
                title=L("Update verfügbar", "Update available"),
                message=L(
                    f"Version v{latest} ist verfügbar (installiert: v{APP_VERSION}).\n\n"
                    "Soll die neue Version jetzt heruntergeladen und geöffnet werden?",
                    f"Version v{latest} is available (installed: v{APP_VERSION}).\n\n"
                    "Download and open the new version now?"),
                ok=L("Herunterladen & öffnen", "Download & open"),
                cancel=L("Abbrechen", "Cancel"))
            if resp == 1:
                threading.Thread(
                    target=self._download_update_worker,
                    args=(asset_url,), daemon=True).start()
        else:
            resp = rumps.alert(
                title=L("Update verfügbar", "Update available"),
                message=L(
                    f"Version v{latest} ist verfügbar (installiert: v{APP_VERSION}).\n\n"
                    "Releases-Seite im Browser öffnen?",
                    f"Version v{latest} is available (installed: v{APP_VERSION}).\n\n"
                    "Open the releases page in the browser?"),
                ok=L("Seite öffnen", "Open page"),
                cancel=L("Abbrechen", "Cancel"))
            if resp == 1:
                subprocess.Popen(["/usr/bin/open", GITHUB_RELEASES_URL])

    def _download_update_worker(self, url):
        from PyObjCTools import AppHelper
        # Nur HTTPS-Downloads von GitHub-Releases zulassen.
        allowed = (
            url.startswith("https://github.com/")
            or url.startswith("https://objects.githubusercontent.com/")
            or url.startswith("https://release-assets.githubusercontent.com/")
        )
        if not allowed or not url.lower().endswith(".dmg"):
            AppHelper.callAfter(self._update_failed)
            return
        raw_name = url.rsplit("/", 1)[-1] or "DesktopProfileManager_update.dmg"
        safe_name = "".join(
            ch for ch in raw_name
            if ch.isalnum() or ch in (".", "_", "-")
        )
        if not (safe_name.lower().endswith(".dmg") and len(safe_name) > 4):
            safe_name = "DesktopProfileManager_update.dmg"
        dest_dir = Path.home() / "Downloads"
        if not dest_dir.exists():
            import tempfile
            dest_dir = Path(tempfile.gettempdir())
        dest = dest_dir / safe_name
        try:
            out = subprocess.run(
                ["/usr/bin/curl", "-fsSL", "--max-time", "180",
                 "-H", "User-Agent: DesktopProfileManager",
                 "-o", str(dest), url],
                capture_output=True, timeout=200,
            )
            if out.returncode != 0:
                AppHelper.callAfter(self._update_failed)
                return
            subprocess.Popen(["/usr/bin/open", str(dest)])
        except Exception:
            AppHelper.callAfter(self._update_failed)

    def on_quit(self, _):
        self._stop_auto_restore()
        rumps.quit_application()

    # ── Auto-Restore Timer ────────────────────────────────────────

    def _start_auto_restore(self):
        self._stop_auto_restore()
        interval_sec = self.config["auto_restore_interval_minutes"] * 60
        self.auto_timer = rumps.Timer(self._auto_restore_tick, interval_sec)
        self.auto_timer.start()

    def _stop_auto_restore(self):
        if self.auto_timer is not None:
            self.auto_timer.stop()
            self.auto_timer = None

    # ── Globale Kurzbefehle (⌘⌃1–9) ───────────────────────────────

    # Tastencodes der Ziffern 1–9 (US-Layout, lagenunabhängig genug)
    _DIGIT_KEYCODES = {18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
                       22: 5, 26: 6, 28: 7, 25: 8}

    def _hotkey_flags(self):
        """Liefert die geforderte Modifier-Maske gemäß Konfiguration."""
        key = self.config.get("hotkey_modifier", "cmd_ctrl")
        mapping = {
            "cmd_ctrl": NSEventModifierFlagCommand | NSEventModifierFlagControl,
            "ctrl": NSEventModifierFlagControl,
            "opt_cmd": NSEventModifierFlagOption | NSEventModifierFlagCommand,
            "ctrl_shift": NSEventModifierFlagControl | NSEventModifierFlagShift,
        }
        return mapping.get(key, mapping["cmd_ctrl"])

    def _hotkey_symbol(self):
        """Anzeige-Symbol der aktuell gewählten Modifier (z. B. '⌘⌃')."""
        return HOTKEY_MODIFIERS.get(
            self.config.get("hotkey_modifier", "cmd_ctrl"), "⌘⌃")

    def _start_hotkeys(self):
        self._stop_hotkeys()
        mask = NSEventMaskKeyDown
        # Alle relevanten Modifier-Bits, die wir auswerten
        all_mods = (NSEventModifierFlagCommand | NSEventModifierFlagControl
                    | NSEventModifierFlagOption | NSEventModifierFlagShift)

        def handler(event):
            try:
                want = self._hotkey_flags()
                flags = event.modifierFlags()
                # Genau die gewünschten Modifier müssen gedrückt sein
                if (flags & all_mods) != want:
                    return
                idx = self._DIGIT_KEYCODES.get(event.keyCode())
                if idx is None:
                    return
                profiles = list_profiles()
                if idx < len(profiles):
                    name = profiles[idx]["name"]
                    self._do_restore(name, notify=True, mark_active=True)
            except Exception:
                pass

        self._hotkey_monitor = NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
            mask, handler
        )

    def _stop_hotkeys(self):
        if self._hotkey_monitor is not None:
            try:
                NSEvent.removeMonitor_(self._hotkey_monitor)
            except Exception:
                pass
            self._hotkey_monitor = None

    def on_toggle_hotkeys(self, _):
        enabled = not self.config.get("hotkeys_enabled", False)
        self.config["hotkeys_enabled"] = enabled
        save_config(self.config)
        if enabled:
            self._start_hotkeys()
            sym = self._hotkey_symbol()
            rumps.notification(
                APP_NAME, L("Kurzbefehle aktiviert", "Shortcuts enabled"),
                L(f"{sym}1 bis {sym}9 stellen die ersten 9 Profile wieder her.",
                  f"{sym}1 to {sym}9 restore the first 9 profiles."))
        else:
            self._stop_hotkeys()
            rumps.notification(APP_NAME,
                               L("Kurzbefehle deaktiviert", "Shortcuts disabled"), "")
        self._build_menu()

    def on_set_hotkey_modifier(self, sender):
        key = getattr(sender, "_hotkey_modifier", None)
        if not key or key not in HOTKEY_MODIFIERS:
            return
        self.config["hotkey_modifier"] = key
        save_config(self.config)
        # Bei aktiven Kurzbefehlen den Monitor neu starten
        if self.config.get("hotkeys_enabled", False):
            self._start_hotkeys()
        self._build_menu()

    # ── Automatisches Umschalten (Zeit / WLAN) ────────────────────

    def _start_auto_switch(self):
        self._stop_auto_switch()
        self._auto_switch_timer = rumps.Timer(self._auto_switch_tick, 60)
        self._auto_switch_timer.start()
        # Sofort einmal prüfen
        self._auto_switch_tick(None)

    def _stop_auto_switch(self):
        if self._auto_switch_timer is not None:
            self._auto_switch_timer.stop()
            self._auto_switch_timer = None

    @staticmethod
    def _time_in_range(value: str) -> bool:
        """Prüft, ob die aktuelle Uhrzeit im Bereich 'HH:MM-HH:MM' liegt."""
        try:
            start_s, end_s = value.split("-")
            sh, sm = (int(x) for x in start_s.strip().split(":"))
            eh, em = (int(x) for x in end_s.strip().split(":"))
        except (ValueError, AttributeError):
            return False
        now = datetime.now()
        cur = now.hour * 60 + now.minute
        start = sh * 60 + sm
        end = eh * 60 + em
        if start <= end:
            return start <= cur < end
        # Über Mitternacht (z. B. 22:00-06:00)
        return cur >= start or cur < end

    def _auto_switch_tick(self, _):
        rules = self.config.get("auto_switch_rules", [])
        profiles = list_profiles()
        # WLAN-Zuordnungen direkt aus den Profilen ableiten
        wifi_map = [(p["name"], p["wifi_ssid"]) for p in profiles if p.get("wifi_ssid")]
        if not rules and not wifi_map:
            return
        ssid = None
        target = None

        # 1. Zeitregeln (haben Vorrang, da explizit terminiert)
        for rule in rules:
            if rule.get("type") != "time":
                continue
            profile = rule.get("profile")
            if profile and self._time_in_range(rule.get("value", "")):
                target = profile
                break

        # 2. WLAN-Zuordnung der Profile
        if target is None and wifi_map:
            ssid = get_current_wifi_ssid() or ""
            if ssid:
                for name, profile_ssid in wifi_map:
                    if ssid == profile_ssid:
                        target = name
                        break

        # 3. Ältere, manuell angelegte WLAN-Regeln (Abwärtskompatibilität)
        if target is None:
            for rule in rules:
                if rule.get("type") != "wifi":
                    continue
                profile = rule.get("profile")
                if not profile:
                    continue
                if ssid is None:
                    ssid = get_current_wifi_ssid() or ""
                if ssid and ssid == rule.get("value", ""):
                    target = profile
                    break

        if target and target != self._last_auto_switch:
            if get_profile_path(target).exists():
                self._last_auto_switch = target
                self._do_restore(target, notify=True, include_apps=False)

    def on_toggle_auto_switch(self, _):
        enabled = not self.config.get("auto_switch_enabled", False)
        self.config["auto_switch_enabled"] = enabled
        save_config(self.config)
        if enabled:
            self._last_auto_switch = None
            self._start_auto_switch()
            rumps.notification(
                APP_NAME, L("Auto-Umschalten aktiviert", "Auto switch enabled"),
                L("Profile werden je nach Zeit/WLAN automatisch gewechselt.",
                  "Profiles are switched automatically based on time/Wi-Fi."))
        else:
            self._stop_auto_switch()
            rumps.notification(APP_NAME,
                               L("Auto-Umschalten deaktiviert", "Auto switch disabled"), "")
        self._build_menu()

    def _prompt_text(self, title, message, default=""):
        """Einfacher Text-Dialog; gibt den eingegebenen Text oder None zurück."""
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)
        NSApp.activateIgnoringOtherApps_(True)
        try:
            win = rumps.Window(
                title=title, message=message, default_text=default,
                ok=L("OK", "OK"), cancel=L("Abbrechen", "Cancel"), dimensions=(220, 24)
            )
            resp = win.run()
            if resp.clicked and resp.text.strip():
                return resp.text.strip()
            return None
        finally:
            NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    def _pick_profile_name(self):
        """Lässt den Benutzer ein vorhandenes Profil per Dropdown auswählen."""
        profiles = [p["name"] for p in list_profiles()]
        if not profiles:
            rumps.notification(APP_NAME, L("Keine Profile", "No profiles"),
                               L("Bitte zuerst ein Profil anlegen.",
                                 "Please create a profile first."))
            return None

        NSApp.setActivationPolicy_(NSApplicationActivationPolicyRegular)
        NSApp.activateIgnoringOtherApps_(True)
        try:
            alert = NSAlert.alloc().init()
            alert.setMessageText_(L("Profil wählen", "Choose profile"))
            alert.setInformativeText_(
                L("Welches Profil soll dieser Regel zugeordnet werden?",
                  "Which profile should be assigned to this rule?"))
            alert.addButtonWithTitle_(L("OK", "OK"))
            alert.addButtonWithTitle_(L("Abbrechen", "Cancel"))

            popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(
                NSMakeRect(0, 0, 240, 26), False)
            popup.addItemsWithTitles_(profiles)
            alert.setAccessoryView_(popup)

            response = alert.runModal()
            if response != NSAlertFirstButtonReturn:
                return None
            selected = popup.titleOfSelectedItem()
            return str(selected) if selected else None
        finally:
            NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    def on_add_time_rule(self, _):
        value = self._prompt_text(
            L("Zeitregel: Profil nach Uhrzeit laden",
              "Time rule: load profile by time of day"),
            L("In welchem Zeitfenster soll ein Profil automatisch geladen werden?\n"
              "Format HH:MM-HH:MM (z. B. 09:00-17:00 für tagsüber):",
              "During which time window should a profile load automatically?\n"
              "Format HH:MM-HH:MM (e.g. 09:00-17:00 for daytime):"),
            "09:00-17:00")
        if not value:
            return
        # Format prüfen: HH:MM-HH:MM
        valid = False
        try:
            start_s, end_s = value.split("-")
            for part in (start_s, end_s):
                h, m = (int(x) for x in part.strip().split(":"))
                if not (0 <= h < 24 and 0 <= m < 60):
                    raise ValueError
            valid = True
        except (ValueError, AttributeError):
            valid = False
        if not valid:
            rumps.notification(APP_NAME, L("Ungültig", "Invalid"),
                               L("Format HH:MM-HH:MM erwartet.",
                                 "Expected format HH:MM-HH:MM."))
            return
        profile = self._pick_profile_name()
        if not profile:
            return
        rules = self.config.get("auto_switch_rules", [])
        rules.append({"type": "time", "value": value, "profile": profile})
        self.config["auto_switch_rules"] = rules
        save_config(self.config)
        self._build_menu()

    def on_add_wifi_rule(self, _):
        current = get_current_wifi_ssid() or ""
        value = self._prompt_text(
            L("WLAN-Regel", "Wi-Fi rule"),
            L("Name des WLANs (SSID):", "Wi-Fi network name (SSID):"),
            current)
        if not value:
            return
        profile = self._pick_profile_name()
        if not profile:
            return
        rules = self.config.get("auto_switch_rules", [])
        rules.append({"type": "wifi", "value": value, "profile": profile})
        self.config["auto_switch_rules"] = rules
        save_config(self.config)
        self._build_menu()

    def on_delete_auto_switch_rule(self, sender):
        idx = getattr(sender, "_rule_index", None)
        rules = self.config.get("auto_switch_rules", [])
        if idx is not None and 0 <= idx < len(rules):
            rules.pop(idx)
            self.config["auto_switch_rules"] = rules
            save_config(self.config)
        self._build_menu()

    def _auto_restore_tick(self, _):
        profile = self.config["auto_restore_profile"]
        # Apps bei Auto-Restore NICHT neu starten, nur Icons/Hintergrund
        self._do_restore(profile, notify=False, include_apps=False)

    def _restore_on_login(self):
        """Stellt Icons beim App-Start wieder her (mit Verzögerung für Finder)."""
        profile = self.config["auto_restore_profile"]
        path = get_profile_path(profile)
        if not path.exists():
            return

        import time

        def task():
            # Warten bis der Finder bereit ist
            time.sleep(8)

            # Finder aktivieren
            try:
                run_applescript('tell application "Finder" to activate')
            except RuntimeError:
                pass
            time.sleep(2)

            max_retries = 3
            for attempt in range(max_retries):
                try:
                    success, failed, error, warning = restore_profile(
                        profile,
                        include_wallpaper=self.config.get("restore_wallpaper", True),
                        include_apps=self.config.get("restore_apps", True),
                    )
                    if not error and success > 0:
                        msg = f"{success} Icons wiederhergestellt"
                        if failed:
                            msg += f", {failed} fehlgeschlagen"
                        rumps.notification(APP_NAME, f"Login-Restore: '{profile}'", msg)
                        return
                    elif attempt < max_retries - 1:
                        time.sleep(5)
                        continue
                    else:
                        rumps.notification(APP_NAME, f"Login-Restore: '{profile}'",
                                         error or "Keine Icons wiederhergestellt")
                except Exception as e:
                    if attempt < max_retries - 1:
                        time.sleep(5)
                        continue
                    rumps.notification(APP_NAME, "Login-Restore Fehler", str(e))

        threading.Thread(target=task, daemon=True).start()

    # ── Sleep/Wake Beobachtung ────────────────────────────────────

    def _register_wake_observer(self):
        """Registriert einen Observer für Wake-from-Sleep Events."""
        self._wake_observer = SleepWakeObserver.alloc().initWithApp_(self)
        NSWorkspace.sharedWorkspace().notificationCenter().addObserver_selector_name_object_(
            self._wake_observer,
            'handleWakeNotification:',
            NSWorkspaceDidWakeNotification,
            None
        )

    def _start_wake_detector(self):
        """Startet einen Timer der Wake-from-Sleep erkennt über Zeitsprünge."""
        self._wake_timer = rumps.Timer(self._check_wake, 10)
        self._wake_timer.start()

    def _check_wake(self, _):
        """Prüft auf Wake-from-Sleep (Zeitsprung) und Screen-Unlock (CGSession)."""
        now = time.time()
        elapsed = now - self._last_check_time
        self._last_check_time = now

        # 1. Zeitsprung-Erkennung: Timer ist 10s, >30s = Sleep/Wake
        if elapsed > 30:
            if self.config.get("restore_on_wake", True):
                self._restore_after_wake()
            return

        # 2. Screen-Lock/Unlock-Erkennung via CGSession-Polling
        try:
            session = _CGSessionCopyCurrentDictionary()
            is_locked = bool(session.get('CGSSessionScreenIsLocked', False)) if session else False
        except Exception:
            is_locked = False

        if self._screen_was_locked and not is_locked:
            # Bildschirm wurde gerade entsperrt
            if self.config.get("restore_on_wake", True):
                self._restore_after_wake()

        self._screen_was_locked = is_locked

    def _restore_after_wake(self):
        """Stellt Icons nach dem Aufwachen aus dem Ruhemodus wieder her."""
        profile = self.config["auto_restore_profile"]
        path = get_profile_path(profile)
        if not path.exists():
            return

        import time

        def task():
            # Warten bis Finder nach dem Aufwachen bereit ist
            time.sleep(3)

            # Finder aktivieren damit Desktop-Items geladen werden
            try:
                run_applescript('tell application "Finder" to activate')
            except RuntimeError:
                pass
            time.sleep(2)

            # Mehrere Versuche mit steigender Wartezeit
            max_retries = 3
            for attempt in range(max_retries):
                try:
                    success, failed, error, warning = restore_profile(
                        profile,
                        include_wallpaper=self.config.get("restore_wallpaper", True),
                        include_apps=False,
                    )
                    if not error and success > 0:
                        msg = f"{success} Icons wiederhergestellt"
                        if failed:
                            msg += f", {failed} fehlgeschlagen"
                        rumps.notification(APP_NAME, f"Wake-Restore: '{profile}'", msg)
                        return
                    elif error:
                        if attempt < max_retries - 1:
                            time.sleep(5)
                            continue
                        rumps.notification(APP_NAME, "Wake-Restore Fehler", error)
                        return
                    else:
                        # success == 0, vielleicht Finder noch nicht bereit
                        if attempt < max_retries - 1:
                            time.sleep(5)
                            continue
                        rumps.notification(APP_NAME, f"Wake-Restore: '{profile}'",
                                         "Keine Icons wiederhergestellt")
                        return
                except Exception as e:
                    if attempt < max_retries - 1:
                        time.sleep(5)
                        continue
                    rumps.notification(APP_NAME, "Wake-Restore Fehler", str(e))

        threading.Thread(target=task, daemon=True).start()


# ─── Haupteinstieg ────────────────────────────────────────────────

def find_icon() -> str | None:
    """Sucht das Icon – funktioniert sowohl als Skript als auch im .app Bundle."""
    candidates = [
        Path(__file__).resolve().parent / "icon.png",                    # Skript-Modus
        Path(__file__).resolve().parent / ".." / "Resources" / "icon.png",  # .app Bundle
    ]
    for p in candidates:
        p = p.resolve()
        if p.exists():
            return str(p)
    return None


if __name__ == "__main__":
    PROFILES_DIR.mkdir(exist_ok=True)
    APP_ICON = find_icon()
    app = DesktopIconManagerApp()
    app.run()
