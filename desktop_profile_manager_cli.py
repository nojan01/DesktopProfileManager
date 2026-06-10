#!/usr/bin/env python3
"""
Desktop Profile Manager CLI for macOS
Speichert und stellt Desktop-Icon-Positionen wieder her.

Copyright (c) 2026 Norbert Jander
Erstellt nach einer Idee von Norbert Jander mit Hilfe eines KI-Agents.
Lizenz: MIT (siehe LICENSE)
    python3 desktop_profile_manager_cli.py save [Profilname]
    python3 desktop_profile_manager_cli.py restore [Profilname]
    python3 desktop_profile_manager_cli.py list
    python3 desktop_profile_manager_cli.py show [Profilname]
    python3 desktop_profile_manager_cli.py delete [Profilname]
"""

import subprocess
import json
import stat
import sys
import os
import time
from datetime import datetime
from pathlib import Path

PROFILES_DIR = Path.home() / ".iconguard"


def run_applescript(script: str) -> str:
    """Führt ein AppleScript aus und gibt das Ergebnis zurück."""
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        raise RuntimeError(f"AppleScript Fehler: {result.stderr.strip()}")
    return result.stdout.strip()


def get_icon_positions() -> dict:
    """Liest alle Desktop-Icon-Positionen über Finder AppleScript."""
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
                print(f"  Warnung: Position für '{name}' konnte nicht gelesen werden.")
    return positions


def set_icon_positions(positions: dict) -> tuple[int, int]:
    """Setzt Desktop-Icon-Positionen über Finder AppleScript.
    Iteriert per Referenz (umgeht macOS 26 Bug bei `item "Name" of desktop`).
    Gibt (erfolgreich, fehlgeschlagen) zurück."""
    if not positions:
        return 0, 0
    entries = []
    for name, pos in positions.items():
        escaped = name.replace('\\', '\\\\').replace('"', '\\"')
        entries.append(f'{{"{escaped}", {pos["x"]}, {pos["y"]}}}')
    targets_literal = "{" + ", ".join(entries) + "}"
    script = f'''
    set targets to {targets_literal}
    set successCount to 0
    set notFound to {{}}
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
            if not foundIt then set end of notFound to tName
        end repeat
    end tell
    set AppleScript's text item delimiters to "||"
    set missing to notFound as text
    set AppleScript's text item delimiters to ""
    return (successCount as text) & linefeed & missing
    '''
    try:
        result = run_applescript(script)
        lines = result.split("\n", 1)
        success = int(lines[0])
        missing = lines[1] if len(lines) > 1 else ""
        missing_names = [n for n in missing.split("||") if n]
        for n in missing_names:
            print(f"  ⚠ '{n}': nicht gefunden")
        return success, len(missing_names)
    except (RuntimeError, ValueError) as e:
        print(f"  ⚠ AppleScript-Fehler: {e}")
        return 0, len(positions)


# ─── Hintergrund + Apps ───────────────────────────────────────────────

def _esc(text: str) -> str:
    """Escaped einen String für AppleScript-Literale."""
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
    """Setzt den Desktop-Hintergrund. Akzeptiert einen Pfad oder eine Liste."""
    if isinstance(wallpaper, str):
        wallpaper = [wallpaper]
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


def get_app_windows() -> dict:
    """Liefert pro Prozessname eine Liste der Fenster-Geometrien (Accessibility nötig)."""
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


_APP_BLACKLIST_NAMES = {"Desktop Profile Manager", "Finder"}


def get_running_apps() -> list[dict]:
    """Liefert die aktuell sichtbaren regulären Apps via AppleScript."""
    script = '''
    tell application "System Events"
        set output to ""
        repeat with proc in (every process whose background only is false)
            try
                set procName to name of proc
                set procPath to (POSIX path of (file of proc))
                set output to output & procName & "||" & procPath & linefeed
            end try
        end repeat
        return output
    end tell
    '''
    try:
        raw = run_applescript(script)
    except RuntimeError:
        return []
    apps = []
    for line in raw.splitlines():
        parts = line.split("||")
        if len(parts) != 2:
            continue
        name, path = parts[0], parts[1]
        if not name or name in _APP_BLACKLIST_NAMES:
            continue
        apps.append({"name": name, "path": path})
    return apps


def capture_apps() -> list[dict]:
    """Erfasst laufende Apps inkl. Fensterposition/-größe."""
    apps = get_running_apps()
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


def launch_apps(apps: list[dict], stagger_delay: float = 1.5) -> int:
    """Startet die angegebenen Apps gestaffelt und stellt ihre Fenster wieder her."""
    launched = 0
    running = {a["name"] for a in get_running_apps()}
    for app in apps:
        target = app.get("path") or app.get("name")
        if not target:
            continue
        already_running = app.get("name") in running
        try:
            subprocess.run(
                ["open", "-g", "-a", target] if already_running else ["open", "-a", target],
                capture_output=True, timeout=20,
            )
            launched += 1
        except (subprocess.SubprocessError, OSError):
            continue
        if not already_running:
            time.sleep(stagger_delay)
    if any(app.get("windows") for app in apps):
        time.sleep(3)
        restore_windows(apps)
    return launched


def hide_other_apps(keep_apps: list[dict]) -> int:
    """Blendet alle laufenden Apps aus, die nicht zum Profil gehören (wie ⌘H)."""
    keep_names = {a["name"] for a in keep_apps}
    hidden = 0
    for app in get_running_apps():
        name = app["name"]
        if name in keep_names:
            continue
        script = (
            'tell application "System Events" to '
            f'set visible of process "{_esc(name)}" to false'
        )
        try:
            run_applescript(script)
            hidden += 1
        except RuntimeError:
            continue
    return hidden


def get_desktop_path() -> Path:
    """Gibt den Pfad zum Desktop-Ordner zurück."""
    return Path.home() / "Desktop"


def get_hidden_items() -> list[str]:
    """Gibt eine Liste aller versteckten Dateien auf dem Desktop zurück."""
    desktop = get_desktop_path()
    hidden = []
    for item in desktop.iterdir():
        if item.name.startswith("."):
            continue  # System-Dateien ignorieren
        try:
            st = item.stat()
            if st.st_flags & stat.UF_HIDDEN:
                hidden.append(item.name)
        except OSError:
            pass
    return sorted(hidden)


def get_all_desktop_items() -> list[str]:
    """Gibt eine Liste aller Dateien auf dem Desktop zurück (sichtbar + versteckt)."""
    desktop = get_desktop_path()
    items = []
    for item in desktop.iterdir():
        if item.name.startswith("."):
            continue
        items.append(item.name)
    return sorted(items)


def hide_item(name: str) -> bool:
    """Versteckt ein Desktop-Icon. Gibt True bei Erfolg zurück."""
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
    """Macht ein verstecktes Desktop-Icon wieder sichtbar. Gibt True bei Erfolg zurück."""
    path = get_desktop_path() / name
    if not path.exists():
        return False
    try:
        st = path.stat()
        os.chflags(path, st.st_flags & ~stat.UF_HIDDEN)
        return True
    except OSError:
        return False


def get_profile_path(name: str) -> Path:
    """Gibt den Pfad zur Profil-Datei zurück."""
    # Sicherheit: Nur einfache Profilnamen erlauben
    safe_name = "".join(c for c in name if c.isalnum() or c in "-_ ")
    if not safe_name:
        raise ValueError("Ungültiger Profilname.")
    return PROFILES_DIR / f"{safe_name}.json"


def cmd_save(profile_name: str = "default"):
    """Speichert die aktuelle Arbeitsumgebung (Icons, Sichtbarkeit, Hintergrund, Apps)."""
    PROFILES_DIR.mkdir(exist_ok=True)
    print("📸 Lese Desktop-Icon-Positionen...")
    positions = get_icon_positions()
    hidden = get_hidden_items()
    print("🖼  Lese Desktop-Hintergrund...")
    wallpaper = get_wallpaper()
    print("🚀 Erfasse laufende Apps...")
    apps = capture_apps()

    if not positions and not hidden and not wallpaper and not apps:
        print("Keine Daten zum Speichern gefunden.")
        return

    profile_path = get_profile_path(profile_name)
    data = {
        "profile": profile_name,
        "saved_at": datetime.now().isoformat(),
        "icon_count": len(positions) + len(hidden),
        "positions": positions,
        "hidden": hidden,
        "wallpaper": wallpaper,
        "apps": apps,
    }
    profile_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    print(f"✅ {len(positions)} sichtbare + {len(hidden)} versteckte Icons gespeichert in Profil '{profile_name}'")
    if hidden:
        print(f"   Versteckt: {', '.join(hidden)}")
    if wallpaper:
        print(f"   🖼  Hintergrund: {len(wallpaper)} Bildschirm(e)")
    if apps:
        print(f"   🚀 Apps: {', '.join(a['name'] for a in apps)}")
    print(f"   Datei: {profile_path}")


def cmd_restore(profile_name: str = "default", with_apps: bool = True,
                with_wallpaper: bool = True, hide_others: bool = False):
    """Stellt die Arbeitsumgebung aus einem Profil wieder her."""
    profile_path = get_profile_path(profile_name)

    if not profile_path.exists():
        print(f"❌ Profil '{profile_name}' nicht gefunden.")
        print("   Verfügbare Profile:")
        cmd_list()
        return

    data = json.loads(profile_path.read_text())
    positions = data.get("positions", {})
    hidden_list = data.get("hidden", [])
    wallpaper = data.get("wallpaper")
    apps = data.get("apps", [])
    saved_at = data.get("saved_at", "unbekannt")

    print(f"🔄 Stelle {len(positions)} Icon-Positionen wieder her...")
    print(f"   Profil: '{profile_name}' (gespeichert: {saved_at})")

    # Sichtbarkeit wiederherstellen: Alle Desktop-Items durchgehen
    all_items = get_all_desktop_items()
    hidden_restored = 0
    unhidden_restored = 0
    for item_name in all_items:
        if item_name in hidden_list:
            if hide_item(item_name):
                hidden_restored += 1
        else:
            if unhide_item(item_name):
                unhidden_restored += 1

    if hidden_restored or unhidden_restored:
        print(f"   👁 Sichtbarkeit: {hidden_restored} versteckt, {unhidden_restored} eingeblendet")

    success, failed = set_icon_positions(positions)

    if with_wallpaper and wallpaper:
        if set_wallpaper(wallpaper):
            print(f"   🖼  Hintergrund wiederhergestellt ({len(wallpaper)} Bildschirm(e))")

    if with_apps and apps:
        print(f"   🚀 Starte {len(apps)} App(s)...")
        launched = launch_apps(apps)
        print(f"   🚀 {launched} App(s) gestartet")

    if hide_others:
        hidden_count = hide_other_apps(apps)
        print(f"   🙈 {hidden_count} andere App(s) ausgeblendet")

    print(f"\n✅ Fertig: {success} erfolgreich", end="")
    if failed:
        print(f", {failed} fehlgeschlagen (Icons möglicherweise nicht mehr vorhanden)")
    else:
        print()


def cmd_list():
    """Listet alle gespeicherten Profile auf."""
    if not PROFILES_DIR.exists():
        print("Keine Profile vorhanden.")
        return

    profiles = sorted(PROFILES_DIR.glob("*.json"))
    if not profiles:
        print("Keine Profile vorhanden.")
        return

    print(f"📋 Gespeicherte Profile ({len(profiles)}):\n")
    for p in profiles:
        try:
            data = json.loads(p.read_text())
            name = data.get("profile", p.stem)
            count = data.get("icon_count", "?")
            saved = data.get("saved_at", "?")
            if saved != "?":
                dt = datetime.fromisoformat(saved)
                saved = dt.strftime("%d.%m.%Y %H:%M")
            extras = []
            if data.get("apps"):
                extras.append(f"{len(data['apps'])} Apps")
            if data.get("wallpaper"):
                extras.append("🖼")
            extra_str = ("  [" + ", ".join(extras) + "]") if extras else ""
            print(f"  • {name:20s}  {count:>3} Icons  ({saved}){extra_str}")
        except (json.JSONDecodeError, ValueError):
            print(f"  • {p.stem:20s}  (Datei beschädigt)")


def cmd_show(profile_name: str = "default"):
    """Zeigt die Icon-Positionen und Sichtbarkeit eines Profils an."""
    profile_path = get_profile_path(profile_name)

    if not profile_path.exists():
        print(f"❌ Profil '{profile_name}' nicht gefunden.")
        return

    data = json.loads(profile_path.read_text())
    positions = data["positions"]
    hidden_list = data.get("hidden", [])

    print(f"📍 Profil '{profile_name}' – {len(positions)} sichtbare Icons:\n")
    for name, pos in sorted(positions.items()):
        print(f"  {name:40s}  ({pos['x']:>5}, {pos['y']:>5})")

    if hidden_list:
        print(f"\n🙈 Versteckte Icons ({len(hidden_list)}):\n")
        for name in hidden_list:
            print(f"  {name}")

    wallpaper = data.get("wallpaper")
    if wallpaper:
        print(f"\n🖼  Hintergrund ({len(wallpaper)} Bildschirm(e)):\n")
        for path in wallpaper:
            print(f"  {path}")

    apps = data.get("apps", [])
    if apps:
        print(f"\n🚀 Apps ({len(apps)}):\n")
        for app in apps:
            win = len(app.get("windows", []))
            win_info = f"  ({win} Fenster)" if win else ""
            print(f"  {app['name']}{win_info}")


def cmd_delete(profile_name: str):
    """Löscht ein gespeichertes Profil."""
    profile_path = get_profile_path(profile_name)

    if not profile_path.exists():
        print(f"❌ Profil '{profile_name}' nicht gefunden.")
        return

    profile_path.unlink()
    print(f"🗑  Profil '{profile_name}' gelöscht.")


def cmd_hide(name: str):
    """Versteckt ein Desktop-Icon."""
    if hide_item(name):
        print(f"🙈 '{name}' wurde versteckt.")
    else:
        print(f"❌ '{name}' nicht auf dem Desktop gefunden oder Zugriff verweigert.")


def cmd_unhide(name: str):
    """Macht ein verstecktes Desktop-Icon wieder sichtbar."""
    if unhide_item(name):
        print(f"👁 '{name}' ist wieder sichtbar.")
    else:
        print(f"❌ '{name}' nicht auf dem Desktop gefunden oder Zugriff verweigert.")


def cmd_hidden():
    """Zeigt alle versteckten Desktop-Icons an."""
    hidden = get_hidden_items()
    if not hidden:
        print("Keine versteckten Icons auf dem Desktop.")
        return
    print(f"🙈 Versteckte Icons ({len(hidden)}):\n")
    for name in hidden:
        print(f"  {name}")


def print_usage():
    print("""
Desktop Profile Manager CLI – Arbeitsumgebungs-Manager für macOS
==============================================================

Verwendung:
  python3 desktop_profile_manager_cli.py save [Profilname]            Arbeitsumgebung speichern (Icons, Hintergrund, Apps)
  python3 desktop_profile_manager_cli.py restore [Profilname] [Opt.]  Arbeitsumgebung wiederherstellen
  python3 desktop_profile_manager_cli.py list                         Alle Profile anzeigen
  python3 desktop_profile_manager_cli.py show [Profilname]            Profil-Details anzeigen
  python3 desktop_profile_manager_cli.py delete <Profilname>          Profil löschen
  python3 desktop_profile_manager_cli.py hide <Dateiname>             Desktop-Icon verstecken
  python3 desktop_profile_manager_cli.py unhide <Dateiname>           Verstecktes Icon einblenden
  python3 desktop_profile_manager_cli.py hidden                       Alle versteckten Icons anzeigen

Optionen für restore:
  --no-apps        Apps nicht starten
  --no-wallpaper   Hintergrund nicht ändern
  --hide-others    Apps, die nicht zum Profil gehören, ausblenden

Profilname ist optional und standardmäßig "default".

Hinweis: Für Fensterpositionen muss das ausführende Programm (z. B. Terminal)
in den Systemeinstellungen unter „Bedienungshilfen“ freigegeben sein.

Beispiele:
  python3 desktop_profile_manager_cli.py save arbeit                  # Speichert als "arbeit"
  python3 desktop_profile_manager_cli.py restore arbeit               # Stellt alles wieder her
  python3 desktop_profile_manager_cli.py restore arbeit --no-apps     # Ohne Apps zu starten
  python3 desktop_profile_manager_cli.py hide "Geheim.pdf"            # Versteckt eine Datei
""")


def main():
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(0)

    args = sys.argv[1:]
    flags = {a for a in args if a.startswith("-")}
    positional = [a for a in args if not a.startswith("-")]

    command = positional[0].lower()
    profile = positional[1] if len(positional) > 1 else "default"
    with_apps = "--no-apps" not in flags
    with_wallpaper = "--no-wallpaper" not in flags
    hide_others = "--hide-others" in flags

    commands = {
        "save": lambda: cmd_save(profile),
        "restore": lambda: cmd_restore(profile, with_apps, with_wallpaper, hide_others),
        "list": cmd_list,
        "show": lambda: cmd_show(profile),
        "delete": lambda: cmd_delete(profile),
        "hide": lambda: cmd_hide(profile) if profile != "default" else print("❌ Bitte Dateiname angeben: hide <Dateiname>"),
        "unhide": lambda: cmd_unhide(profile) if profile != "default" else print("❌ Bitte Dateiname angeben: unhide <Dateiname>"),
        "hidden": cmd_hidden,
        "help": print_usage,
    }

    if command in ("-h", "--help") or command in commands:
        if command in ("-h", "--help"):
            print_usage()
        else:
            commands[command]()
    else:
        print(f"❌ Unbekannter Befehl: '{command}'")
        print_usage()
        sys.exit(1)


if __name__ == "__main__":
    main()
