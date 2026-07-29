# Desktop Profile Manager – Hilfe & Bedienungsanleitung

Desktop Profile Manager ist eine **Menüleisten-App** für macOS, mit der du komplette
Arbeitsumgebungen als **Profile** speicherst und mit einem Klick wiederherstellst:
Desktop-Icon-Positionen, versteckte Icons, Hintergrundbild, gestartete Apps inkl.
Fensterposition, Browser-Tabs sowie diverse Systemeinstellungen.

Die App hat **kein Dock-Symbol**. Du bedienst sie ausschließlich über das Symbol in
der macOS-Menüleiste oben rechts. Ein Klick darauf öffnet das Menü.

---

## Inhaltsverzeichnis

1. [Erste Schritte](#erste-schritte)
2. [Benötigte Berechtigungen](#benötigte-berechtigungen)
3. [Das Menü im Überblick](#das-menü-im-überblick)
4. [Profil-Schnellauswahl](#profil-schnellauswahl)
5. [Einstellungen](#einstellungen)
   - [Profil speichern](#profil-speichern)
   - [Profil wiederherstellen](#profil-wiederherstellen)
   - [Desktop-Icons ein-/ausblenden](#desktop-icons-ein-ausblenden)
   - [Apps für Profile auswählen](#apps-für-profile-auswählen)
   - [Profil-Widget anzeigen](#profil-widget-anzeigen)
   - [Widget kompakt (nur Emojis)](#widget-kompakt-nur-emojis)
   - [Auto-Wiederherstellen](#auto-wiederherstellen)
   - [Auto-Restore nur Desktop-Symbole](#auto-restore-nur-desktop-symbole)
   - [Intervall](#intervall)
   - [Auto-Restore-Profil](#auto-restore-profil)
   - [Profil bearbeiten](#profil-bearbeiten)
   - [Profil löschen](#profil-löschen)
   - [Profil exportieren](#profil-exportieren)
   - [Profil importieren](#profil-importieren)
   - [Wiederherstellungs-Schalter](#wiederherstellungs-schalter)
   - [App-Startverzögerung](#app-startverzögerung)
   - [Beim Anmelden starten](#beim-anmelden-starten)
   - [Kurzbefehle 1–9](#kurzbefehle-19)
   - [Tastenkombination](#tastenkombination)
   - [Auto-Umschalten (Zeit/WLAN)](#auto-umschalten-zeitwlan)
   - [Sprache](#sprache)
   - [Nach Updates suchen](#nach-updates-suchen)
   - [Statuszeile](#statuszeile)
6. [Hilfe / Über / Beenden](#hilfe--über--beenden)
7. [Das Profil-Erstellungs-Fenster im Detail](#das-profil-erstellungs-fenster-im-detail)
8. [Wo werden meine Daten gespeichert?](#wo-werden-meine-daten-gespeichert)
9. [Häufige Fragen (FAQ)](#häufige-fragen-faq)

---

## Erste Schritte

1. App starten – das App-Symbol erscheint oben rechts in der Menüleiste.
2. Desktop-Icons so anordnen, wie du sie haben möchtest.
3. **Einstellungen › Profil speichern › Neues Profil …** wählen.
4. Namen und Emoji vergeben, Inhalte auswählen, speichern.
5. Profil später über das Menü (oben in der Schnellauswahl) oder das Widget
   per Klick wiederherstellen.

---

## Benötigte Berechtigungen

Für die volle Funktion benötigt die App eine Berechtigung:

- **Bedienungshilfen** (Systemeinstellungen › Datenschutz & Sicherheit ›
  Bedienungshilfen): Wird benötigt, um Fensterpositionen/-größen von Apps zu lesen
  und wiederherzustellen sowie Apps ein-/auszublenden.
- **Automatisierung**: Für Browser-Tabs fragt macOS bei Bedarf nach der Freigabe für
  Safari, Google Chrome oder Microsoft Edge. Sie wird benötigt, um Tabs zu lesen und
  wieder zu öffnen.

Beim ersten Start, der diese Funktionen nutzt, fragt macOS automatisch nach der
Erlaubnis. Ohne diese Berechtigung funktionieren Icon-Positionen, Hintergrundbild
und App-Start weiterhin – nur die exakte Fensterwiederherstellung nicht.

---

## Das Menü im Überblick

Das Menü besteht von oben nach unten aus:

1. **Profil-Schnellauswahl** – alle gespeicherten Profile zum direkten Wiederherstellen.
2. **⚙️ Einstellungen** – das große Untermenü mit allen Funktionen (siehe unten).
3. **Hilfe – Profil erstellen** – kurze Schnellanleitung.
4. **Über Desktop Profile Manager** – Versions- und Lizenzinfos.
5. **Beenden** – App schließen.

---

## Profil-Schnellauswahl

Ganz oben im Menü stehen alle gespeicherten Profile, jeweils mit einem `▶︎`-Symbol,
dem gewählten Emoji und dem Profilnamen. 

- **Klick auf ein Profil** stellt es sofort wieder her (Icons, ggf. Hintergrund,
  Apps usw. – je nach den gespeicherten und globalen Einstellungen).
- Das **aktuell aktive Profil** ist farblich (in der Akzentfarbe) hervorgehoben.
- Sind die **Kurzbefehle** aktiviert, steht rechts neben den ersten neun Profilen
  zusätzlich die jeweilige Tastenkombination (z. B. `⌘⌃1`).

Solange noch kein Profil existiert, ist dieser Bereich leer.

---

## Einstellungen

Alle folgenden Punkte befinden sich im Untermenü **⚙️ Einstellungen**.

### Profil speichern

Untermenü **💾 Profil speichern …**:

- **Neues Profil …** – Öffnet das Profil-Erstellungs-Fenster (siehe
  [unten](#das-profil-erstellungs-fenster-im-detail)). Hier legst du Name, Emoji,
  Inhalte, optional die WLAN-Zuordnung, Apps und Browser-Tabs fest. Profilnamen
  dürfen Buchstaben, Zahlen, Leerzeichen, Bindestriche und Unterstriche enthalten.
- **Überschreiben: \<Profil\>** – Speichert den **aktuellen** Desktop-Zustand in ein
  bereits vorhandenes Profil und übernimmt dabei dessen bisherige Einstellungen
  (welche Inhalte erfasst werden, Emoji, App-Auswahl usw.). Praktisch, um ein Profil
  schnell zu aktualisieren, ohne das Fenster zu öffnen.

### Profil wiederherstellen

Untermenü **🔄 Profil wiederherstellen**: listet alle Profile auf. Ein Klick stellt
das gewählte Profil wieder her – identisch zur Schnellauswahl oben, nur gebündelt
in einem Untermenü. Ist noch kein Profil vorhanden, steht hier ein Hinweis.

### Desktop-Icons ein-/ausblenden

**👁 Desktop-Icons ein-/ausblenden …** öffnet ein Fenster, in dem alle Objekte auf
dem Schreibtisch aufgelistet sind. Pro Eintrag kannst du festlegen, ob das Icon
sichtbar oder versteckt sein soll. So blendest du einzelne Symbole gezielt aus,
ohne sie zu löschen. Der Zustand kann anschließend Teil eines Profils werden.

### Apps für Profile auswählen

**🚀 Apps für Profile auswählen …** öffnet ein Fenster mit allen aktuell laufenden
Apps. Hier definierst du eine globale **Ausschlussliste**: Abgehakte Apps werden
beim Speichern neuer Profile **nicht** mit erfasst (z. B. Hintergrund-Tools oder die
Entwicklungsumgebung). Diese Auswahl gilt als Vorgabe für neue Profile.

### Profil-Widget anzeigen

**🧩 Profil-Widget anzeigen** (Schalter) blendet ein frei verschiebbares Widget auf
dem Desktop ein. Es enthält pro Profil einen Knopf zum direkten Wiederherstellen.

- Das Widget ist **randlos und transparent** – sichtbar sind nur die Knöpfe.
- Du verschiebst es per **Ziehen mit der Maus**; die Position wird gespeichert.
- Das aktive Profil ist im Widget farblich hervorgehoben.
- Die Sichtbarkeit bleibt über App-Neustarts hinweg erhalten.

### Widget kompakt (nur Emojis)

**🔳 Widget kompakt (nur Emojis)** (Schalter) schaltet das Widget zwischen zwei
Darstellungen um:

- **Aus:** normale Ansicht mit Emoji **und** Profilname.
- **Ein:** kompakte Ansicht mit **großen Emojis** ohne Text – ideal als platzsparende
  Schnellzugriffsleiste. Der Profilname erscheint als Tooltip, wenn du mit der Maus
  über das Emoji fährst.

### Auto-Wiederherstellen

**⏱ Auto-Wiederherstellen** (Schalter) ist der **Hauptschalter für die
zeitgesteuerte, wiederkehrende** Wiederherstellung. Ist er an, läuft im Hintergrund
ein **Timer**, der das unter *Auto-Restore-Profil* gewählte Profil immer wieder in
dem unter *Intervall* eingestellten Takt anwendet – solange die App läuft. Nützlich,
um eine „Soll-Ordnung" des Desktops dauerhaft zu erzwingen.

> **Wichtig – das steuert nur den Intervall-Timer.** Das Wiederherstellen *beim
> Login* und *nach dem Ruhemodus* sind davon unabhängig und werden über die
> separaten Schalter *🔁 Beim Login wiederherstellen* bzw. *😴 Nach Ruhemodus
> wiederherstellen* gesteuert. Diese funktionieren auch dann, wenn
> *Auto-Wiederherstellen* ausgeschaltet ist.

Kurz gesagt, die Einträge greifen so ineinander:

- **⏱ Auto-Wiederherstellen** → *ob* der Intervall-Timer läuft
- **⏰ Intervall** → *wie oft* (z. B. alle 30 Min.)
- **📋 Auto-Restore-Profil** → *welches* Profil
- **🧩 Auto-Restore nur Desktop-Symbole** → *was* wiederhergestellt wird

### Auto-Restore nur Desktop-Symbole

**🧩 Auto-Restore nur Desktop-Symbole** (Schalter) legt fest, **was** die
*automatische* Wiederherstellung (Intervall-Timer, Login und Ruhemodus) anwendet:

- **Aus** (Standard): Es wird das komplette Profil angewandt – Icon-Positionen,
  Hintergrund, Apps und Systemzustand.
- **An**: Es werden **nur die Desktop-Symbol-Positionen** wiederhergestellt –
  Hintergrund, Apps und Systemzustand bleiben unangetastet.

Das **manuelle** Wiederherstellen über die Schnellauswahl ist davon nicht betroffen
und stellt weiterhin alles wieder her.

### Intervall

Untermenü **⏰ Intervall**: legt fest, **wie oft** das Auto-Wiederherstellen läuft.
Auswahl: 5, 10, 15, 30, 60, 120 oder 240 Minuten. Der aktive Wert ist mit einem
Häkchen markiert.

### Auto-Restore-Profil

Untermenü **📋 Auto-Restore-Profil**: bestimmt, **welches** Profil beim automatischen
Wiederherstellen (sowie beim Login und nach dem Ruhemodus) verwendet wird. Es wird
genau ein Profil ausgewählt (Häkchen). Mit **(Kein)** lässt sich die Auswahl
zurücknehmen – dann findet **keine** automatische Wiederherstellung mehr statt (weder
per Intervall noch beim Login oder nach dem Ruhemodus). Ohne gespeicherte Profile
steht hier ein Hinweis.

### Profil bearbeiten

Untermenü **✏️ Profil bearbeiten**: öffnet das Bearbeiten-Fenster für das gewählte
Profil. Wichtig:

- Die **gespeicherten Icon-Positionen, versteckten Icons und das Hintergrundbild
  bleiben unverändert erhalten** – der Desktop wird *nicht* neu erfasst.
- Geändert werden nur **Metadaten**: Name, Emoji, WLAN-Zuordnung, App-Auswahl,
  erfasste Systemzustände, Browser-Tabs und die Inhalts-Optionen.
- Du kannst ein Profil hier auch **umbenennen**; Zeit- und WLAN-Regeln werden dabei
  aktualisiert.

### Profil löschen

Untermenü **🗑 Profil löschen**: entfernt das gewählte Profil nach einer
Sicherheitsabfrage endgültig. **Dies kann nicht rückgängig gemacht werden.**

### Profil exportieren

Untermenü **📤 Profil exportieren**: speichert das gewählte Profil als `.json`-Datei
an einem von dir gewählten Ort. So kannst du Profile sichern oder an einen anderen
Mac weitergeben.

### Profil importieren

**📥 Profil importieren …** lädt eine zuvor exportierte `.json`-Profildatei und fügt
sie deinen Profilen hinzu.

### Wiederherstellungs-Schalter

Eine Gruppe globaler Schalter, die festlegen, **was** bei einer Wiederherstellung
passiert:

- **🔁 Beim Login Icons wiederherstellen** – Wendet beim Anmelden automatisch das
  Auto-Restore-Profil an.
- **😴 Nach Ruhemodus wiederherstellen** – Stellt das Auto-Restore-Profil wieder her,
  nachdem der Mac aus dem Ruhezustand aufgewacht ist.
- **🖼 Hintergrund mit wiederherstellen** – Setzt beim Wiederherstellen auch das im
  Profil gespeicherte Hintergrundbild.
- **🚀 Apps beim Wiederherstellen starten** – Startet die im Profil gespeicherten Apps
  (und stellt nach Möglichkeit deren Fenster wieder her).
- **🙈 Andere Apps beim Wechsel ausblenden** – Blendet alle nicht zum Profil gehörenden
  Apps aus (wie ⌘H), ohne sie zu beenden.
- **⛔ Andere Apps beim Wechsel beenden** – Beendet alle nicht zum Profil gehörenden
  Apps. (Vorsicht: ungespeicherte Arbeit kann verloren gehen.)

> Hinweis: *Ausblenden* und *Beenden* schließen sich gegenseitig sinnvoll aus – wähle
> in der Regel höchstens eine der beiden Optionen.

### App-Startverzögerung

Untermenü **⏳ App-Startverzögerung**: bestimmt die Pause **zwischen** dem Starten
einzelner Apps beim Wiederherstellen (Keine, 0,5, 1, 1,5, 2, 3 oder 5 Sekunden). Eine
größere Verzögerung entlastet das System, wenn viele oder schwere Programme gestartet
werden.

### Beim Anmelden starten

**🔓 Beim Anmelden starten** (Schalter) richtet einen **LaunchAgent** ein, sodass die
App automatisch startet, sobald du dich an deinem Mac anmeldest. Der Schalter ist nur
aktiv, wenn macOS den Dienst geladen hat; bei Fehlern zeigt die App eine Meldung an.

### Kurzbefehle 1–9

**⌨️ Kurzbefehle \<Symbol\>1–9** (Schalter) aktiviert globale Tastenkürzel: Mit der
gewählten Modifikator-Kombination plus den Zifferntasten **1–9** stellst du die ersten
neun Profile direkt wieder her – egal, welche App gerade im Vordergrund ist. Bei
aktivierten Kurzbefehlen werden die Kombinationen auch in der Schnellauswahl angezeigt.

### Tastenkombination

Untermenü **⌨️ Tastenkombination**: wählt den **Modifikator** für die Kurzbefehle.
Zur Auswahl stehen:

- **⌘⌃** (Befehl + Ctrl)
- **⌃** (Ctrl)
- **⌥⌘** (Option + Befehl)
- **⌃⇧** (Ctrl + Shift)

jeweils kombiniert mit den Tasten 1–9.

### Auto-Umschalten (Zeit/WLAN)

Untermenü **🕓 Auto-Umschalten (Zeit/WLAN)**: schaltet Profile automatisch anhand der
Uhrzeit oder des verbundenen WLANs um.

- **Aktiviert** (Schalter) – schaltet die gesamte Auto-Umschaltung ein/aus.
- **➕ Zeitregel hinzufügen … (Profil nach Uhrzeit)** – Legt eine Regel an, die zu
  einer bestimmten Uhrzeit/Zeitspanne ein bestimmtes Profil aktiviert.
- **📶 WLAN: im Profil bearbeiten festlegen** – Hinweis: Die WLAN-Zuordnung legst du
  pro Profil im Bearbeiten-/Erstellen-Fenster im Feld *WLAN-Name* fest. Verbindet sich
  der Mac mit diesem WLAN, wird das zugehörige Profil aktiviert.
- Darunter werden die **aktiven WLAN-Zuordnungen** (`📶 WLAN → Profil`) sowie die
  angelegten **Zeit- und WLAN-Regeln** aufgelistet. Ein Klick auf eine Regel mit dem
  Zusatz *(löschen)* entfernt sie.

### Sprache

Untermenü **🌐 Sprache**: stellt die Oberflächensprache ein:

- **System** – folgt der Sprache deines Macs (Deutsch oder sonst Englisch).
- **Deutsch**
- **Englisch**

### Nach Updates suchen

**⬆️ Nach Updates suchen …** prüft online, ob eine neuere Version verfügbar ist, und
zeigt das Ergebnis an. Nach deiner Bestätigung lädt die App die DMG-Datei direkt in den Ordner
**Downloads** und öffnet sie. Ziehe anschließend die App nach **Programme** und starte sie neu.
Nur wenn ein Release keine DMG-Datei enthält, wird auf die Release-Seite verwiesen.

### Statuszeile

**ℹ️ \<Status\>** ist eine reine Anzeige (nicht klickbar). Sie zeigt, ob das
Auto-Wiederherstellen aktiv ist und – falls ja – mit welchem Profil und in welchem
Intervall (z. B. „Auto: 'Standard' alle 30 Min."). Andernfalls steht dort
„Auto-Restore: Aus".

---

## Hilfe / Über / Beenden

Am unteren Ende des Hauptmenüs:

- **Hilfe – Profil erstellen** – zeigt eine kurze Schritt-für-Schritt-Anleitung zum
  Anlegen eines Profils.
- **Über Desktop Profile Manager** – zeigt Version, Funktionsüberblick, den Hinweis
  zur Bedienungshilfen-Berechtigung, das Copyright (© 2026 Norbert Jander) und die
  Lizenz (**MIT**).
- **Beenden** – schließt die App (Tastenkürzel **⌘Q**, wenn das Menü geöffnet ist).

---

## Das Profil-Erstellungs-Fenster im Detail

Über *Profil speichern › Neues Profil …* bzw. *Profil bearbeiten* öffnet sich ein
Fenster mit folgenden Feldern:

- **Emoji-Feld** – das Symbol, das in Menü und Widget vor dem Profilnamen erscheint.
  Über den danebenliegenden **😀-Knopf** öffnest du die macOS-Emoji-Auswahl.
- **Profilname** – der Anzeigename des Profils (Pflichtfeld).
- **WLAN-Name (optional)** – Trägst du hier ein WLAN ein, wird das Profil beim Verbinden
  mit diesem Netzwerk automatisch geladen (sofern *Auto-Umschalten* aktiv ist).
- **Was soll gespeichert/wiederhergestellt werden?** – Schalter für die Inhalte:
  - **Icon-Positionen**
  - **Versteckte Icons**
  - **Hintergrundbild**
  - **Apps**
  - **Browser-Tabs (Safari, Chrome, Edge)** – Speichert alle geöffneten Web- und
    lokalen Datei-Tabs (`http(s)://`, `file://`) der aktuell laufenden unterstützten
    Browser. Beim Wiederherstellen werden sie als neue Tabs geöffnet; vorhandene Tabs
    bleiben erhalten. Firefox-Tabs können ohne Browser-Erweiterung nicht zuverlässig
    ausgelesen werden. Datei-URLs werden nur für lokale, absolute Pfade erfasst.
- **Systemzustand** – optionale Schalter wie Dark Mode, Lautstärke, Helligkeit,
  „Nicht stören", Dock und Desktop-Ansicht.
- **App-Liste** – Auswahl, welche der laufenden Apps zum Profil gehören sollen
  (mit *Alle auswählen*).

Beim **Bearbeiten** eines bestehenden Profils bleiben die bereits gespeicherten
Icon-/Hintergrunddaten erhalten; nur die hier sichtbaren Angaben werden aktualisiert.

---

## Wo werden meine Daten gespeichert?

Alle Daten liegen lokal in deinem Benutzerordner:

```
~/.iconguard/
  <Profilname>.json     # je ein Profil pro Datei
  _config.json          # globale Einstellungen
```

Die Profile liegen im JSON-Format vor und können bei Bedarf manuell gesichert
oder bearbeitet werden.

---

## Häufige Fragen (FAQ)

**Das App-Symbol steht nicht ganz links in der Menüleiste.**
Halte **⌘** gedrückt und ziehe das Symbol an die gewünschte Stelle. macOS merkt
sich die Position dauerhaft.

**Eine App (z. B. Safari) startet beim Wiederherstellen nicht.**
Apps werden bevorzugt über ihre Bundle-ID gestartet, was auch bei Systemupdates
zuverlässig funktioniert. Stelle sicher, dass *Apps beim Wiederherstellen starten*
aktiviert ist.

**Fensterpositionen werden nicht wiederhergestellt.**
Erteile der App die Berechtigung unter *Systemeinstellungen › Datenschutz &
Sicherheit › Bedienungshilfen*.

**Meine Browser-Tabs werden nicht gespeichert oder geöffnet.**
Aktiviere im Profil *Browser-Tabs (Safari, Chrome, Edge)*, lasse den Browser beim
Speichern geöffnet und aktiviere *Apps beim Wiederherstellen starten*. Erteile die
angefragte Automatisierungsberechtigung. Firefox-Tabs werden nicht automatisch erfasst.

**Das Widget ist nach einem Neustart wieder ausgeblendet.**
Das sollte nicht passieren – die Sichtbarkeit wird dauerhaft gespeichert. Schalte das
Widget bei Bedarf über *Einstellungen › Profil-Widget anzeigen* wieder ein.

---

*Copyright © 2026 Norbert Jander · Lizenz: MIT*
