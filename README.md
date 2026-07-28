# Unraid Server Health Monitor (USHM)

Zentrales Monitoring für Unraid – Cache, Docker, AppData-Wachstum, Alarme per Mail & Pushover.

**Version:** 1.0.0 · **Kein Docker** – Bash-Skript für [User Scripts](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/)

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

## Features (v1.0)

| Bereich | Prüfung |
|--------|---------|
| Cache SSD | freier Speicher |
| Docker | Image-Belegung, Container-Logs |
| AppData | Top-N + Wachstum seit letztem Lauf |
| Historie | CSV |
| Mail | SMTP, STARTTLS, HTML-Report |
| Pushover | Daily / Warnung / Kritisch |

Roadmap: [docs/ROADMAP.md](docs/ROADMAP.md)

## Schnellstart

```bash
cd /tmp
git clone https://github.com/PaulG67/unraid-server-health-monitor.git ushm
cd ushm
bash install.sh
nano /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --test-notify
```

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
