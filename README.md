# Unraid Server Health Monitor (USHM)

Zentrales Monitoring für Unraid – Cache, Docker, AppData-Wachstum, Alarme per Mail & Pushover.

**Version:** 2.1.0 · **Kein Docker** – Bash-Skript für [User Scripts](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/)

📘 **Weitergeben / Nachbauen:** → **[Installations- & Konfigurationsanleitung](docs/INSTALL.md)**

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
Status
🟢 OK
```

## Features (v2.1)

| Bereich | Prüfung |
|--------|---------|
| Cache SSD | freier Speicher (nutzbar, RAID1-richtig) |
| Docker | Image-Belegung, Container-Logs |
| AppData | Top-N + Wachstum seit letztem Lauf |
| **Inventar** | Disks hinzugekommen / entfernt / ersetzt (beim Start) |
| **Disks** | Parity + Data + Cache: Status, I/O-`numErrors`, Temp, Deltas |
| **SMART** | Health, Temp, Reallocated/Pending/CRC **aller** Disks + Änderungen |
| Historie | CSV inkl. inventory/parity/smart |
| Mail | SMTP, STARTTLS, HTML-Report |
| Pushover | Daily / Warnung / Kritisch |

Roadmap: [docs/ROADMAP.md](docs/ROADMAP.md)

## Schnellstart (Installation)

```bash
cd /tmp
rm -rf ushm
git clone https://github.com/PaulG67/unraid-server-health-monitor.git ushm
cd ushm
bash install.sh
nano /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --test-notify
```

## Update (wichtig)

**Nicht** im Install-Ordner unter `/boot/...` `git pull` ausführen – dort ist oft kein GitHub-Remote (Fehler wie `Permission denied (publickey)` / steckengebliebene alte Version).

Immer frisch von GitHub per **HTTPS** und Installer (`config.conf` bleibt erhalten):

```bash
cd /tmp
rm -rf ushm
git clone https://github.com/PaulG67/unraid-server-health-monitor.git ushm
cd ushm
cat VERSION   # erwartet 2.1.0+
bash install.sh
cat /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/VERSION
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --dry-run 2>&1 | grep -E 'USHM v|Cache:|Inventar|Disk|SMART'
```

Details: **[docs/INSTALL.md §5 Updates](docs/INSTALL.md#5-updates)**

Zeitplan in User Scripts (Custom), z.B. täglich 08:00:

```text
0 8 * * *
```

Ausführliche Schritte, Pushover/Mail, Schwellwerte und Fehlerbehebung: **[docs/INSTALL.md](docs/INSTALL.md)**

## Installationsort auf Unraid

```text
/boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/
```

## Lizenz

MIT
