# Installation & Konfiguration

Anleitung für **Unraid Server Health Monitor (USHM)** – zum Weitergeben und Nachbauen.

**Repo:** https://github.com/PaulG67/unraid-server-health-monitor

---

## Was ist USHM?

USHM ist **kein Docker-Container**, sondern ein modulares **Bash-Skript** für das Unraid-Plugin **User Scripts**.

Es prüft regelmäßig:

- Cache-SSD (freier Speicher)
- Docker-Image-Belegung & Container-Logs
- AppData-Größe (Top-Verzeichnisse) und Wachstum seit dem letzten Lauf
- schreibt CSV-Historie
- sendet bei Bedarf **HTML-Mail** und/oder **Pushover**

---

## Voraussetzungen

| Bedarf | Details |
|--------|---------|
| Unraid | getestet mit aktuellen Unraid-Versionen |
| Plugin | **User Scripts** (Community Apps → „User Scripts“) |
| Optional Mail | `python3` (meist vorhanden) oder `msmtp` |
| Optional Pushover | `curl` (meist vorhanden) + [Pushover](https://pushover.net)-Account |

---

## 1. Installation

Im **Unraid-Terminal** oder per SSH (als `root`):

```bash
cd /tmp
rm -rf ushm
git clone https://github.com/PaulG67/unraid-server-health-monitor.git ushm
cd ushm
bash install.sh
```

Der Installer kopiert alles nach:

```text
/boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/
```

Struktur nach der Installation:

```text
Unraid-Server-Health-Monitor/
├── ushm.sh                 # Hauptskript
├── script                  # Wrapper für User Scripts
├── description
├── config/
│   ├── config.conf         # deine Konfiguration (lokal, nicht im Git)
│   └── config.conf.example
├── lib/                    # Module
├── modules/                # Inventar + Array/Disks + SMART (v2.1)
└── data/
    ├── history/            # CSV-Historie
    └── state/              # Snapshots für Wachstum
```

> `/boot/...` liegt auf dem Unraid-USB-Stick und überlebt Reboots.

---

## 2. Konfiguration

```bash
nano /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf
```

Alternativ Vorlage aus dem Repo:

```bash
cp /tmp/ushm/config/config.conf.ready \
  /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf
nano /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf
```

### 2.1 Nur Pushover

1. Account auf https://pushover.net  
2. **Your User Key** notieren (Startseite)  
3. Unter **Apps** eine Application anlegen → **API Token/Key**  
4. In `config.conf`:

```ini
PUSHOVER_ENABLED=true
PUSHOVER_TOKEN=dein_application_token
PUSHOVER_USER=dein_user_key
PUSHOVER_DAILY=true

MAIL_ENABLED=false
```

| Variable | Bedeutung |
|----------|-----------|
| `PUSHOVER_TOKEN` | Application API Token (App) |
| `PUSHOVER_USER` | Your User Key (Konto) |

Nicht vertauschen – sonst: `application token is invalid`.

### 2.2 Nur Mail (SMTP)

```ini
MAIL_ENABLED=true
SMTP_SERVER=smtp.dein-provider.de
SMTP_PORT=587
SMTP_USER=dein@email.de
SMTP_PASS=dein_passwort_oder_app_passwort
SMTP_TLS=true
MAIL_FROM=dein@email.de
MAIL_TO=dein@email.de
MAIL_ON=warn

PUSHOVER_ENABLED=false
```

Hinweise:

- Port **587** + `SMTP_TLS=true` (STARTTLS) ist der Standardweg
- `MAIL_FROM` oft = `SMTP_USER`
- Gmail/Google: App-Passwort verwenden
- `MAIL_ON`: `warn` | `crit` | `always` | `daily`  
  - `warn` (früher Default): Mail **nur** bei Warnung/Kritisch  
  - `daily` / `always`: Mail auch bei Status OK (wie Pushover Daily Report)

### 2.3 Schwellwerte (Defaults)

```ini
CACHE_WARN=20          # Warnung wenn weniger als 20 % Cache frei
CACHE_CRIT=10
DOCKER_WARN=70         # Warnung wenn Docker-Image ≥ 70 % voll
DOCKER_CRIT=90
APP_WARN_MB=500        # Warnung bei AppData-Wachstum ≥ 500 MB je App
APP_CRIT_MB=2000
LOG_WARN_MB=500        # Warnung bei Container-Logs gesamt ≥ 500 MB
LOG_CRIT_MB=2000
```

Pfade – wie `df -hT` und `ls /mnt/` (exakte Schreibweise, Linux ist case-sensitive):

```ini
# Beispiel Multi-Pool: Pool heißt „cacheintern“
CACHE_PATH=/mnt/cacheintern
APPDATA_PATH=/mnt/user/appdata
DOCKER_PATH=/var/lib/docker
```

Hinweise Cache:

| Symptom | Lösung |
|---------|--------|
| Pool heißt z. B. `cacheintern`, nicht `cache` | `CACHE_PATH=/mnt/cacheintern` (wie `df -hT`) |
| `/mnt/Cacheintern` → 0 GB | Groß/Klein falsch; Pfad wie unter `/mnt/` |
| „von ~1.8 TB“ bei 2×1 TB **RAID1** | alte Version (&lt; 1.0.6) – Update (Abschnitt 5); nutzbar ~1 TB |
| Falscher kleiner Pool (~30 GB) | `CACHE_PATH` auf den großen Pool setzen |

Ab **v1.0.6** misst USHM den Cache mit Kernel-`statvfs` / `df` (nutzbare Größe, RAID1-richtig).

---

## 3. Tests

### 3.1 Scan ohne Benachrichtigung

```bash
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --dry-run
```

Erwartet: Fortschritt `[1/7]…[7/7]` und Text-Dashboard inkl. **Inventar**, **Disks** und **SMART**.  
AppData-Scan kann bei großen Containern (Immich, Plex, …) **1–5 Minuten** dauern.

### Disks, Inventar & SMART (v2.1)

Standardmäßig aktiv (`USHM_INVENTORY_ENABLED`, `USHM_ARRAY_ENABLED`, `USHM_SMART_ENABLED`):

| Was | Quelle | Alarm |
|-----|--------|--------|
| Inventar-Vollständigkeit | `disks.ini` vs. `data/state/disk_inventory` | Disk **hinzu** / **fehlt** / **ersetzt** |
| Array-I/O aller Disks | `numErrors` (Parity, Data, Cache) | vorhanden / **Anstieg** |
| Disk-Status | `status` / `color` | disabled / rot |
| SMART aller Disks | `smartctl` | Reallocated, Pending, Uncorrectable, CRC, Temp |
| SMART-Änderung | `data/state/smart_*.env` | Wert **steigt** → Crit/Warn |

Report gruppiert nach **Parity / Data / Cache**. `parity2` wird automatisch erkannt.  
Default `SMART_SCOPE=all` (Standby-Disks werden **nicht** aufgeweckt). Für nur Parity: `SMART_SCOPE=parity`.

Voraussetzung SMART: Paket **smartmontools** (`smartctl` im Pfad).

### 3.2 Mail & Pushover testen

```bash
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --test-notify
```

Erwartet: Test-Mail und/oder Pushover-Nachricht.  
Beide Kanäle müssen in der Config mit `*_ENABLED=true` aktiv sein.

---

## 4. Zeitplan (User Scripts)

1. Unraid WebUI → **Settings → User Scripts**
2. Eintrag **Unraid-Server-Health-Monitor** öffnen  
   (wird vom Installer angelegt; falls leer, siehe unten)
3. Schedule → **Custom**:

```text
0 8 * * *
```

= täglich um **08:00**

Weitere Beispiele:

| Cron | Bedeutung |
|------|-----------|
| `0 7 * * *` | täglich 07:00 |
| `0 */12 * * *` | alle 12 Stunden |
| `30 6 * * 1` | montags 06:30 |

### Falls du ein neues leeres Script anlegst

Name z.B. `Unraid-Server-Health-Monitor`, Inhalt:

```bash
#!/bin/bash
USHM="/boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor"

if [[ ! -f "${USHM}/ushm.sh" ]]; then
  echo "USHM nicht installiert. Bitte zuerst install.sh ausführen."
  exit 1
fi

exec bash "${USHM}/ushm.sh" "$@"
```

---

## 5. Updates

**Wichtig:** Der Install-Ordner unter `/boot/config/.../Unraid-Server-Health-Monitor/` ist **kein** GitHub-Checkout zum `git pull`. Dort oft:

- fremder Remote (`git@backup…` → `Permission denied (publickey)`)
- steckenbleibende alte `VERSION` (z. B. 1.0.2)
- `install.sh` im gleichen Ordner kopiert nur denselben Stand auf sich selbst

### Korrektes Update (immer so)

```bash
# 1) Frische Kopie von GitHub (HTTPS, kein SSH-Key nötig)
cd /tmp
rm -rf ushm
git clone https://github.com/PaulG67/unraid-server-health-monitor.git ushm
cd ushm

# 2) Version im Clone prüfen
cat VERSION

# 3) Nach /boot installieren (config.conf wird NICHT überschrieben)
bash install.sh

# 4) Installierte Version und Cache-Messung prüfen
cat /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/VERSION
bash /boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh --dry-run 2>&1 | grep -E 'USHM v|Cache:'
```

Erwartung:

- `VERSION` und Log `USHM v…` gleich und aktuell (z. B. **1.0.6**)
- Cache-Zeile ≈ `df -hT /mnt/<pool>` (bei RAID1 **nicht** Summe beider SSDs)

Optional – welche Mounts es gibt:

```bash
df -hT /mnt/* 2>/dev/null | grep -vE 'user|disk[0-9]|disks|remotes'
```

---

## 6. Befehle (Kurzreferenz)

| Befehl | Zweck |
|--------|--------|
| `ushm.sh --dry-run` | voller Check, keine Benachrichtigungen |
| `ushm.sh --test-notify` | nur Mail/Pushover testen |
| `ushm.sh` | voller Check + ggf. Alarme |
| `ushm.sh --help` | Hilfe |

Installationspfad der ausführbaren Datei:

```text
/boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/ushm.sh
```

---

## 7. Exit-Codes

| Code | Bedeutung |
|------|-----------|
| `0` | OK |
| `1` | mindestens eine Warnung |
| `2` | mindestens ein kritischer Alarm |

---

## 8. Historie / Daten

| Datei | Inhalt |
|-------|--------|
| `data/history/summary.csv` | Kennzahlen je Lauf |
| `data/history/appdata_YYYY-MM-DD.csv` | App-Größen |
| `data/history/alerts.csv` | ausgelöste Alarme |
| `data/state/` | letzter AppData-Snapshot (für Wachstum) |

Beim **ersten** Lauf gibt es noch kein Wachstum – ab dem **zweiten** Lauf erscheinen Deltas.

---

## 9. Fehlerbehebung

| Symptom | Ursache / Lösung |
|---------|------------------|
| Script „hängt“ ohne Ausgabe | oft langer AppData-Scan – aktualisieren (Fortschrittslogs) und warten |
| `application token is invalid` | `PUSHOVER_TOKEN` / `PUSHOVER_USER` vertauscht |
| SMTP `TimeoutError` | Host/Port prüfen: `nc -vz smtp.example.com 587`. Bei Port **465** in der Config `SMTP_SSL=true` setzen. Unraid neu versuchen oder `SMTP_RETRIES=3` / `SMTP_TIMEOUT=60`. Manche Provider sind nach langen Scans langsam – USHM retried automatisch. |
| Keine Mail trotz OK-Status | `MAIL_ON=warn` sendet nur bei Warnung/Crit – Test mit `--test-notify` oder `MAIL_ON=always` |
| Script in User Scripts leer | Installer ausführen oder Wrapper von Abschnitt 4 einfügen |
| `ushm.sh: No such file or directory` unter `/tmp/user.scripts/...` | User Scripts kopiert nur `script` nach `/tmp`. Wrapper muss den **absoluten** Pfad unter `/boot/config/...` aufrufen (Installer ab Fix 2026-07-28). Sofort-Fix: Inhalt von Abschnitt 4 in das Script einfügen |
| `git pull` → `Permission denied (publickey)` / alte VERSION | Remote im `/boot`-Ordner ist nicht GitHub. Update wie Abschnitt 5: `/tmp` + `git clone https://github.com/PaulG67/...` + `install.sh` |
| Cache „von 1.8 TB“ bei 2×1 TB RAID1 | alte Version (&lt; 1.0.6) oder Btrfs Device-Summe. Update auf ≥1.0.6, Log muss aktuelle `USHM v…` zeigen |
| SMART übersprungen / fehlt | `smartctl` installieren (Nerd Tools / smartmontools). Standby-Disks werden bewusst nicht aufgeweckt |
| Parity „keine Disk“ | Array gestoppt oder keine Parity in `disks.ini` – Main-Tab prüfen |

---

## 10. Sicherheit

- Secrets nur in der **lokalen** `config.conf` auf dem Server
- Diese Datei ist **nicht** im GitHub-Repo (`.gitignore`)
- Im Repo liegen nur leere Vorlagen (`config.conf.example` / `config.conf.ready`)
- Repo und Anleitung dürfen geteilt werden – **keine** Passwörter/Tokens mitgeben

---

## Lizenz

MIT – siehe [LICENSE](../LICENSE).
