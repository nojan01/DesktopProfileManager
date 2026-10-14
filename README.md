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
- **Browser-Tabs** – Web- und lokale Datei-Tabs (`http(s)://`, `file://`) sowie Browser-Fensterpositionen aus Safari, Google Chrome und Microsoft Edge pro Profil sichern. Beim Wiederherstellen wird der Browser regulär beendet und einmal mit dem gespeicherten Tab-Satz neu gestartet. Firefox wird nicht unterstützt.
- **Systemzustand** – Dark Mode, Lautstärke, Helligkeit, Dock und Desktop-Ansicht pro Profil sichern
- **Icons verstecken** – Einzelne Desktop-Dateien ein-/ausblenden
- **Tastenkombinationen** – Die ersten 9 Profile per Hotkey laden (Modifier wählbar: ⌘⌃, ⌃, ⌥⌘, ⌃⇧)
- **Auto-Umschalten** – Profile automatisch nach Uhrzeit (Zeitregeln) oder Netzwerk laden: WLAN (Auswahl aus den bekannten WLANs), Kabel oder beides; Kabel hat Vorrang (WLAN-Erkennung benötigt die Ortungsdienste-Freigabe). Optional schaltet ein Profil das WLAN passend aus (Kabel) bzw. ein (WLAN); wird das Kabel getrennt, kommt das WLAN automatisch zurück
- **Auto-Restore** – Automatische Wiederherstellung in konfigurierbaren Intervallen (5–240 Min)
- **Autostart** – Optionaler Start beim Login via macOS LaunchAgent
- **Menüleisten-App** – Läuft unauffällig in der Menüleiste (kein Dock-Icon)
- **Serielle Profilwechsel** – Während einer Wiederherstellung sind weitere Profilwechsel gesperrt, damit Browser- und Fensteraktionen nicht überlappen
- **Mehrsprachig** – Deutsch/Englisch (folgt der Systemsprache, manuell umschaltbar)

> **Hinweis:** Für das Speichern/Wiederherstellen von Fensterpositionen und für
> Tastenkombinationen muss Desktop Profile Manager in den Systemeinstellungen unter
> *Datenschutz & Sicherheit › Bedienungshilfen* freigegeben sein.
> Unterstützt werden Safari, Google Chrome und Microsoft Edge. Browser-Tabs benötigen zusätzlich die von
> macOS abgefragte Automatisierungsfreigabe. Firefox wird ohne Browser-Erweiterung nicht unterstützt.
> Apps werden nur bei manuellem Restore und beim Login gestartet – nicht beim Intervall-Restore, nach dem
> Ruhemodus oder beim Auto-Umschalten. Andere Apps werden nur bei einem manuellen Wechsel beendet.

## Installation

### DMG (empfohlen)
1. Das aktuelle DMG unter [GitHub Releases](https://github.com/nojan01/DesktopProfileManager/releases/latest) herunterladen oder `build_dmg.sh` ausführen
2. `DesktopProfileManager-Swift-<Version>.dmg` öffnen
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
- Die Versionsnummer steht nur in `Sources/DesktopProfileManager/Config.swift` (`appVersion`); die Build-Skripte lesen sie dort aus

## Lizenz / License

Dieses Projekt ist unter der [MIT-Lizenz](LICENSE) veröffentlicht. Der vollständige, verbindliche
englische Lizenztext befindet sich in [LICENSE](LICENSE).

This project is released under the [MIT License](LICENSE). The complete, authoritative English
license text is available in [LICENSE](LICENSE).

Erstellt nach einer Idee von Norbert Jander mit Hilfe eines KI-Agents.
