# Desktop Profile Manager

macOS Menu Bar App zum Speichern und Wiederherstellen kompletter Arbeitsumgebungen – Desktop-Icon-Positionen, Hintergrund und Apps.

## Features

- **Profile speichern** – Desktop-Icon-Positionen als benannte Profile sichern
- **Profile wiederherstellen** – Gespeicherte Positionen jederzeit wiederherstellen
- **Schnellauswahl** – Profile direkt aus dem Menüleisten-Icon laden; das aktive Profil wird blau hervorgehoben
- **Emoji-Symbole** – Jedem Profil ein eigenes Emoji als Erkennungssymbol zuweisen (per Klick-Emoji-Auswahl)
- **Desktop-Hintergrund** – Hintergrundbild pro Profil speichern & wiederherstellen
- **Apps & Fenster** – Laufende Apps inkl. Fensterposition/-größe sichern und beim Wiederherstellen starten
- **Icons verstecken** – Einzelne Desktop-Dateien ein-/ausblenden
- **Tastenkombinationen** – Die ersten 9 Profile per Hotkey laden (Modifier wählbar: ⌘⌃, ⌃, ⌥⌘, ⌃⇧)
- **Auto-Umschalten** – Profile automatisch nach Uhrzeit (Zeitregeln) oder nach verbundenem WLAN laden
- **Auto-Restore** – Automatische Wiederherstellung in konfigurierbaren Intervallen (5–240 Min)
- **Autostart** – Optionaler Start beim Login via macOS LaunchAgent
- **Menüleisten-App** – Läuft unauffällig in der Menüleiste (kein Dock-Icon)
- **CLI-Modus** – Kommandozeilen-Interface für Scripting

> **Hinweis:** Für das Speichern/Wiederherstellen von Fensterpositionen muss Desktop Profile Manager
> in den Systemeinstellungen unter *Datenschutz & Sicherheit › Bedienungshilfen* freigegeben sein.
> Apps werden nur bei manuellem Restore und beim Login gestartet – nicht bei jedem Auto-Restore.

## Installation

### DMG (empfohlen)
1. `build_dmg.sh` ausführen (erfordert Python 3 + venv)
2. Die erstellte `DesktopProfileManager-1.2.0.dmg` öffnen
3. App nach `/Programme` ziehen
4. Aus Launchpad starten

### Entwicklung
```bash
# Setup
python3 -m venv .venv
source .venv/bin/activate
pip install rumps pyobjc-framework-Cocoa

# GUI starten
python3 desktop_profile_manager_app.py

# CLI nutzen
python3 desktop_profile_manager_cli.py save "Mein Profil"      # Icons, Hintergrund & Apps sichern
python3 desktop_profile_manager_cli.py restore "Mein Profil"   # alles wiederherstellen
python3 desktop_profile_manager_cli.py restore "Mein Profil" --no-apps        # ohne Apps zu starten
python3 desktop_profile_manager_cli.py restore "Mein Profil" --no-wallpaper   # ohne Hintergrund
python3 desktop_profile_manager_cli.py show "Mein Profil"      # Details inkl. Apps/Hintergrund
python3 desktop_profile_manager_cli.py list
```

### CLI-Optionen für `restore`

| Option | Wirkung |
|--------|---------|
| `--no-apps` | Gespeicherte Apps werden nicht gestartet |
| `--no-wallpaper` | Desktop-Hintergrund wird nicht geändert |

## Dateien

| Datei | Beschreibung |
|-------|-------------|
| `desktop_profile_manager_app.py` | Haupt-App (Menüleiste) |
| `desktop_profile_manager_cli.py` | CLI-Version |
| `setup_app.py` | py2app Build-Konfiguration |
| `build_dmg.sh` | Build-Script für .app + DMG |
| `create_icon.py` | Icon-Generator (icns + png) |
| `setup.py` | venv + Dependency Installer |
| `start.sh` | Schnellstart-Script |

## Technologie

- Python 3 + [rumps](https://github.com/jaredks/rumps) (Menu Bar Framework)
- AppleScript für Finder-Integration (`desktop position`), Hintergrund und Fenster (`System Events`)
- `NSWorkspace` (PyObjC) zum Erfassen laufender Apps
- py2app für macOS .app Bundle
- macOS LaunchAgent für Autostart

## Lizenz

MIT License – Copyright (c) 2026 Norbert Jander

Erstellt nach einer Idee von Norbert Jander mit Hilfe eines KI-Agents.
