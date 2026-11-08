# Plexo für iOS

Native iPhone-App (SwiftUI), nachgebaut nach [anmolkapil/plexo](https://github.com/anmolkapil/plexo) (MIT).
Lädt Dateien schneller herunter, indem **WLAN und Mobilfunk gleichzeitig** genutzt werden (plus Ethernet per USB-Adapter).

## So funktioniert es (wie bei Plexo)

Plexo teilt die Datei in Blöcke und lädt verschiedene Blöcke gleichzeitig über jedes Netzwerk (HTTP-Range-Requests).
Jede Verbindung ist auf iOS über `Network.framework` fest an WLAN, Mobilfunk oder Ethernet gebunden.

- Streams holen sich Blöcke aus einer gemeinsamen Warteschlange → schnellere Netzwerke laden automatisch mehr
- Start mit 4 Streams pro Netzwerk, Verdopplung bis 16, solange alle Daten liefern; lehnt der Server ab (429/503/403), wird reduziert und nach 1 Minute wieder erhöht
- Gegen Ende „rennen“ freie Streams langsamen Blöcken hinterher – wer zuerst fertig ist, gewinnt
- Server ohne Range-Unterstützung: ein Stream
- Mehr Tempo gibt es nur, wenn jedes Netzwerk seine eigene Internetverbindung hat (WLAN-Router + Mobilfunk ✓)

## Zwei Engines – stabil auch im Hintergrund

- **Hintergrund (iOS Background-Session):** Die Datei wird in parallele Teile zerlegt (Standard 6), iOS lädt sie selbst – weiter bei gesperrtem Bildschirm, in anderen Apps und sogar wenn iOS Plexo beendet. Abbrüche werden mit Resume-Daten fortgesetzt, fertige Teile in die Datei eingesetzt.
- **Turbo (WLAN + Mobilfunk):** solange Plexo im Vordergrund ist. Wechselst du die App, werden die restlichen Teile automatisch an die Hintergrund-Engine übergeben – nichts geht verloren. Zurück in der App: „Turbo“-Knopf im Download.

Nur wenn du Plexo im App-Umschalter wegwischst, stoppt iOS alle Downloads; beim nächsten Öffnen geht es an derselben Stelle weiter.

## Funktionen

| Plexo (Desktop) | Plexo iOS |
|---|---|
| Mehrere Netzwerke kombinieren, live an/aus | ✅ WLAN, Mobilfunk, Ethernet – pro Download umschaltbar |
| Netzwerke umbenennen, Farben | ✅ |
| Live-Tempo, Restzeit, Fortschritt pro Netzwerk, Blockgitter, Diagramm | ✅ |
| Automatische Stream-Anzahl, Racing langsamer Blöcke | ✅ |
| Pause/Fortsetzen auch nach Neustart | ✅ |
| Abgelaufene Links ersetzen ohne Fortschrittsverlust | ✅ „Link ersetzen“ |
| Warteschlange, gleichzeitige Downloads, Massenaktionen | ✅ |
| Speed-Limit global und pro Netzwerk, Langsam-Modus | ✅ |
| Datenvolumen pro Tag/Woche/Monat | ✅ (ideal für Mobilfunk) |
| Browser-Integration mit Sitzungs-Cookies | ✅ eingebauter Browser fängt Downloads ab, Link lange drücken → „Mit Plexo laden“ |
| Torrents, Magnet, Usenet (NZB), Telegram | ❌ noch nicht |
| Zeitplan | ❌ noch nicht |

Extra: **Dateien-Tab** – Dateimanager mit ZIP/RAR-Entpacker (RAR4/RAR5, mehrteilig, Passwort), ZIP erstellen,
Ordner anlegen, Umbenennen, Verschieben, Kopieren, Löschen und Zugriff auf beliebige Ordner des iPhones.

Links von außen: `plexo://add?url=https://…`

## IPA herunterladen

Die App wird komplett auf GitHub gebaut – kein Mac nötig.

1. Auf dem iPhone in Safari öffnen: **Releases → latest → `Plexo.ipa`**
   (direkt: `https://github.com/Amoo71/blockmash/releases/download/latest/Plexo.ipa`)
2. LiveContainer → `+` → `Plexo.ipa` aus *Downloads* wählen → starten.
3. Beim ersten Download Mobilfunk-Zugriff erlauben (Einstellungen › Mobilfunk › LiveContainer).

## Hinweise

- Hintergrund-Downloads laufen über die Background-Session des Host-Programms. Am zuverlässigsten mit normal installierter IPA (SideStore/AltStore); in LiveContainer funktioniert es, solange LiveContainer nicht weggewischt wird.
- Mobilfunk-Downloads verbrauchen Datenvolumen – setze unter *Netzwerke › Mobilfunk* ein Limit.
- Falls Ordner verknüpfen / Datei-Import in LiveContainer nicht reagiert: App in LiveContainer lange drücken → Einstellungen → „Fix File Picker“.

## Aufbau

```
project.yml                         XcodeGen-Projekt
Plexo/Network/NetworkMonitor.swift  Netzwerke erkennen, Einstellungen, Datenvolumen
Plexo/Network/HTTPConnection.swift  HTTP/1.1-Client, an ein Netzwerk gebunden (Network.framework)
Plexo/Engine/                       Probe, Blockplan, DownloadJob (Streams, Racing), DownloadManager, Limits
Plexo/Files/                        Dateimanager, ZIP (ZIPFoundation), RAR (UnRAR)
Plexo/Views/                        SwiftUI-Oberfläche
Vendor/unrar/                       offizieller UnRAR-Quellcode (RARLAB, nur Entpacken)
.github/workflows/build-ipa.yml     macOS-Build → Plexo.ipa
```
