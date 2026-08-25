# Desktop Profile Manager

Native **Swift/AppKit** macOS Menu Bar App zum Speichern und Wiederherstellen kompletter Arbeitsumgebungen – Desktop-Icon-Positionen, Hintergrund, Apps und Systemzustand.

[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-yellow.svg)](LICENSE)

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE). Copyright © 2026 Norbert Jander.

## Features

- **Profile speichern** – Desktop-Icon-Positionen als benannte Profile sichern
- **Profile wiederherstellen** – Gespeicherte Positionen jederzeit wiederherstellen
- **Schnellauswahl** – Profile direkt aus dem Menüleisten-Icon laden; das aktive Profil wird blau hervorgehoben
- **Profil-Widget** – Schwebendes Panel auf dem Desktop mit einem Button pro Profil zum direkten Anklicken (frei verschiebbar, Position wird gemerkt); zwei Varianten: normal (Emoji + Name) oder kompakt (nur Emojis) zum Platzsparen
- **Emoji-Symbole** – Jedem Profil ein eigenes Emoji als Erkennungssymbol zuweisen
- **Desktop-Hintergrund** – Hintergrundbild pro Profil speichern & wiederherstellen
- **Apps & Fenster** – Laufende Apps inkl. Fensterposition/-größe sichern und beim Wiederherstellen starten (optional andere Apps ausblenden/beenden)
- **Browser-Tabs** – Web- und lokale Datei-Tabs (`http(s)://`, `file://`) aus Safari, Chrome und Edge pro Profil sichern und beim Wiederherstellen als alleinigen Tab-Satz des Profils öffnen
- **Systemzustand** – Dark Mode, Lautstärke, Helligkeit, Nicht stören, Dock und Desktop-Ansicht pro Profil sichern
- **Icons verstecken** – Einzelne Desktop-Dateien ein-/ausblenden
- **Tastenkombinationen** – Die ersten 9 Profile per Hotkey laden (Modifier wählbar: ⌘⌃, ⌃, ⌥⌘, ⌃⇧)
- **Auto-Umschalten** – Profile automatisch nach Uhrzeit (Zeitregeln) oder nach verbundenem WLAN laden
- **Auto-Restore** – Automatische Wiederherstellung in konfigurierbaren Intervallen (5–240 Min)
- **Autostart** – Optionaler Start beim Login via macOS LaunchAgent
- **Menüleisten-App** – Läuft unauffällig in der Menüleiste (kein Dock-Icon)
- **Mehrsprachig** – Deutsch/Englisch (folgt der Systemsprache, manuell umschaltbar)

> **Hinweis:** Für das Speichern/Wiederherstellen von Fensterpositionen und für
> Tastenkombinationen muss Desktop Profile Manager in den Systemeinstellungen unter
> *Datenschutz & Sicherheit › Bedienungshilfen* freigegeben sein.
> Browser-Tabs benötigen zusätzlich die von macOS abgefragte Automatisierungsfreigabe; Firefox-Tabs
> werden ohne Browser-Erweiterung nicht automatisch erfasst.
> Apps werden nur bei manuellem Restore und beim Login gestartet – nicht bei jedem Auto-Restore.

## Installation

### DMG (empfohlen)
1. Das Script `build_dmg.sh` ausführen
2. Die erstellte `DesktopProfileManager-Swift-1.5.1.dmg` öffnen
3. App nach `/Programme` ziehen
4. Aus Launchpad starten

### Entwicklung
```bash
# App bauen und als .app-Bundle verpacken
./build_app.sh
open "dist/Desktop Profile Manager.app"

# Oder direkt mit dem Swift Package Manager bauen/starten
swift build
swift run

# DMG-Installationsimage erstellen
./build_dmg.sh
```

## Daten

Profile und Einstellungen liegen unter:

```
~/.iconguard/
  <Profilname>.json     # einzelne Profile
  _config.json          # Einstellungen
```

## Projektstruktur

| Pfad | Beschreibung |
|------|-------------|
| `Sources/DesktopProfileManager/` | Quellcode (Swift/AppKit) |
| `Resources/` | Hilfe-Dateien (HTML, DE/EN) |
| `Package.swift` | Swift Package Manager Konfiguration |
| `build_app.sh` | Build-Script für das `.app`-Bundle |
| `build_dmg.sh` | Build-Script für `.app` + DMG |

## Technologie

- Swift 5.9 + AppKit (Menüleisten-App via `NSStatusItem`)
- Swift Package Manager (`.executableTarget`)
- `NSWorkspace` zum Erfassen laufender Apps
- AppleScript für Finder-Integration (Desktop-Icon-Positionen), Hintergrund und Fenster
- macOS LaunchAgent für Autostart
- Ziel-OS: macOS 12+

## Lizenz / License

Dieses Projekt ist unter der [MIT-Lizenz](LICENSE) veröffentlicht. Der vollständige, verbindliche
englische Lizenztext befindet sich in [LICENSE](LICENSE).

This project is released under the [MIT License](LICENSE). The complete, authoritative English
license text is available in [LICENSE](LICENSE).

Erstellt nach einer Idee von Norbert Jander mit Hilfe eines KI-Agents.
