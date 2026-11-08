# Pledo für iOS

Native iPhone-/iPad-App (SwiftUI), nachgebaut nach [fxsth/pledo](https://github.com/fxsth/pledo) – dem Plex-Downloader.
Lädt Filme, Serien, Staffeln, einzelne Episoden und Playlists von allen Plex-Servern, auf die dein Konto Zugriff hat, direkt aufs Gerät.

## Funktionen (wie pledo)

| pledo (Web/.NET) | Pledo iOS |
|---|---|
| Login über plex.tv (OAuth, kein Passwort in der App) | ✅ plus Benutzername/Passwort (inkl. 2FA) oder Token |
| Sync aller Server, Bibliotheken, Filme, Serien, Episoden, Playlists in lokale DB | ✅ lokaler JSON-Cache |
| Schnellste Serververbindung finden (lokal / remote / Relay) | ✅ parallele Verbindungsprüfung |
| Hintergrund-Sync der Verbindungen | ✅ beim App-Start und per Pull-to-Refresh |
| Download von Filmen, Serien, Staffeln, Episoden, Playlists | ✅ |
| Mehrere Dateiversionen, bevorzugte Auflösung/Codec | ✅ |
| Dateistruktur-Templates (Film-Ordner, Serie/Season) | ✅ |
| Download-Warteschlange, Verlauf, Abbrechen | ✅ plus Fortsetzen nach Fehlern, Geschwindigkeit, Restzeit |
| „Im Browser herunterladen“ | ✅ als „Direktlink kopieren / im Browser öffnen“ (lange auf eine Version drücken) |
| Suche | ✅ über Filme, Serien und Episoden |

### Dateien-Tab (Dateimanager)

- Pledo-Ordner durchsuchen und beliebige **Ordner vom iPhone verknüpfen** (Auf meinem iPhone, iCloud Drive, USB-Stick …)
- **ZIP entpacken** und **ZIP erstellen** (einzelne Dateien, Ordner oder Mehrfachauswahl)
- **RAR entpacken** (RAR4 + RAR5, mehrteilige Archive `.part1.rar`, passwortgeschützte Archive)
- **Neuer Ordner, Umbenennen, Verschieben, Kopieren, Löschen** – einzeln (lange drücken / wischen) oder per Mehrfachauswahl
- Dateien aus der Dateien-App **importieren**, Vorschau (QuickLook), Teilen / Öffnen in anderen Apps
- Fortschrittsanzeige mit Abbrechen

Heruntergeladene Dateien landen im Dokumente-Ordner der App (`Filme/…`, `Serien/<Serie>/Season N/…`) und sind in der **Dateien-App** sichtbar. Von dort kannst du sie z. B. mit VLC oder Infuse abspielen.

## IPA herunterladen

Die App wird komplett auf GitHub gebaut – du brauchst keinen Mac.

1. Öffne auf dem iPhone den Release **„latest“** dieses Repos (Releases → *Pledo iOS – neuester Build*) und lade `Pledo.ipa` herunter.
   Alternativ: Actions → *Build iOS IPA* → letzter Lauf → Artifact `Pledo-ipa` (ist dann gezippt).
2. In **LiveContainer**: `+` → `Pledo.ipa` aus der Dateien-App wählen → App starten.
3. Unter *Übersicht* → *Mit Plex anmelden* → auf plex.tv bestätigen → der Sync startet automatisch.

Ein neuer Build entsteht bei jedem Push oder manuell über *Actions → Build iOS IPA → Run workflow*.

## Hinweise

- iOS pausiert Downloads, sobald die App im Hintergrund ist. Lass Pledo offen; die Option *Bildschirm während Downloads anlassen* ist standardmäßig an. Abgebrochene Verbindungen werden automatisch fortgesetzt (5 Versuche, wie bei pledo).
- In LiveContainer liegen die Dateien unter *Dateien → LiveContainer → Data → Application → … → Documents*.
- Falls „Ordner verknüpfen“ bzw. der Datei-Import in LiveContainer nicht reagiert: in LiveContainer die App lange drücken → Einstellungen → **„Fix File Picker“** aktivieren.
- Die IPA ist unsigniert. LiveContainer signiert sie selbst; für AltStore/SideStore funktioniert sie ebenfalls.

## Aufbau

```
project.yml                  XcodeGen-Projektdefinition
Pledo/PlexClient.swift       plex.tv- und Plex-Server-API (Login, Ressourcen, Bibliotheken, Paging)
Pledo/LibraryStore.swift     Metadaten-Cache und Sync
Pledo/DownloadManager.swift  Download-Warteschlange, Wiederholungen, Dateipfade
Pledo/Files/                 Dateimanager (Operationen, ZIP via ZIPFoundation, RAR)
Pledo/Views/                 SwiftUI-Oberfläche
Vendor/unrar/                offizieller UnRAR-Quellcode (RARLAB, nur Entpacken – siehe license.txt)
Vendor/RarBridge/            kleine C-Brücke zwischen unrar und Swift
.github/workflows/build-ipa.yml  macOS-Build → Pledo.ipa
```

Lokal mit Mac bauen: `brew install xcodegen && xcodegen generate && open Pledo.xcodeproj`.
