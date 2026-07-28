# Unraid Server Health Monitor (USHM)

Zentrales Monitoring für deinen Unraid-Homeserver – Cache, Docker, AppData-Wachstum, Alarme per Mail & Pushover.

**Version:** 1.0.0

```
=========================================
 Unraid Server Health Monitor
=========================================

Server
✓ Online

-----------------------------------------
Cache SSD
████████░░░░  81 %
758 GB frei

-----------------------------------------
Docker Image
█████░░░░░░░  42 %

-----------------------------------------
Top AppData
Plex                 74.0 GB
Immich               46.0 GB
...

-----------------------------------------
Status
🟢 OK
```

## Warum?

Mit vielen Containern (Immich, Paperless, Plex, Jellyfin, Sonarr, …) merkst du Speicherprobleme oft zu spät. USHM prüft regelmäßig kritische Pfade und meldet auffälliges Wachstum frühzeitig.

## Features (v1.0)

| Bereich | Was wird geprüft |
|--------|-------------------|
| Cache SSD | Belegung / freier Speicher |
| Docker | Image-Belegung, Writable Layer, Container-Logs |
| AppData | Top 20 größte Verzeichnisse |
| Wachstum | Delta seit dem letzten Lauf |
| Historie | CSV für spätere Diagramme |
| Mail | SMTP, STARTTLS, HTML-Report |
| Pushover | Daily / Warnung / Kritisch mit Prioritäten |

Schwellwerte sind frei konfigurierbar. Roadmap: [docs/ROADMAP.md](docs/ROADMAP.md).

## Voraussetzungen

- Unraid mit **User Scripts** Plugin (empfohlen)
- Optional: `curl` (Pushover), `python3` oder `msmtp` (Mail)
- Optional ab v2.0: `smartctl`

## Installation

Auf dem Unraid-Server (als root), z.B. nach `git clone` nach `/tmp/ushm`:

```bash
cd /tmp/ushm
bash install.sh
```

Der Installer legt an:

```
/boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/
├── ushm.sh
├── script              # User-Scripts-Wrapper
├── config/config.conf
├── lib/
├── modules/
└── data/
```

## Konfiguration

```bash
nano /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf
```

Wichtige Einstellungen:

```ini
MAIL_ENABLED=true
SMTP_SERVER=smtp.example.com
SMTP_PORT=587
SMTP_USER=...
SMTP_PASS=...
MAIL_FROM=ushm@example.com
MAIL_TO=you@example.com

PUSHOVER_ENABLED=true
PUSHOVER_TOKEN=...
PUSHOVER_USER=...

CACHE_WARN=20
CACHE_CRIT=10
DOCKER_WARN=70
DOCKER_CRIT=90
APP_WARN_MB=500
APP_CRIT_MB=2000
LOG_WARN_MB=500
LOG_CRIT_MB=2000
```

Vollständige Vorlage: [`config/config.conf.example`](config/config.conf.example).

## Nutzung

### Manuell / Test

```bash
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --dry-run
```

### User Scripts

1. Unraid → **Settings → User Scripts**
2. Script **Unraid-Server-Health-Monitor** wählen
3. Schedule z.B. **Daily** um 07:00

### Exit-Codes

| Code | Bedeutung |
|------|-----------|
| 0 | Alles OK |
| 1 | Mindestens eine Warnung |
| 2 | Mindestens ein kritischer Alarm |

## Historie

Unter `data/history/`:

- `summary.csv` – ein Zeile pro Lauf (Cache %, Docker %, AppData, …)
- `appdata_YYYY-MM-DD.csv` – Größen je App
- `alerts.csv` – ausgelöste Alarme

Daraus lassen sich später Diagramme bauen (v3.0 Dashboard).

## Projektstruktur

```
ushm.sh                 # Einstieg
install.sh              # Unraid-Installer
config/config.conf.example
lib/                    # Cache, Docker, AppData, Growth, Mail, …
modules/                # SMART / Array / Dashboard (Stubs für v2+)
docs/ROADMAP.md
```

## Versionen

| Version | Fokus |
|---------|--------|
| **1.0** | Cache, Docker, AppData, Alarme, Historie |
| **1.5** | Container-Neustarts, gestoppte Container, Log-Details |
| **2.0** | SMART (Temp, Life, TBW, Fehler) |
| **2.5** | Array (Parity, Errors, Rebuild) |
| **3.0** | HTML-Dashboard + Diagramme |

## Lizenz

MIT – nutze und erweitere es für deinen Homeserver.
