# Changelog

Alle wesentlichen Änderungen an USHM werden hier dokumentiert.

## [2.1.0] – 2026-11-11

### Added

- **Disk-Inventar** beim Start: erkennt hinzugekommene, entfernte und ersetzte Disks (Slot/ID) und alarmiert.
- **Alle Disks** im Report: Parity / Data / Cache gruppiert mit Status, I/O-`numErrors`, Temp und Deltas.
- **SMART für alle Disks** (`SMART_SCOPE=all` Default): gruppiert, Standby ohne Spin-up, Kurzfassung in Pushover.
- Config: `USHM_INVENTORY_ENABLED`, `DISK_ERROR_WARN`/`CRIT`; Historie `inventory.csv`.

### Changed

- Default `SMART_SCOPE=parity` → `all`.
- Report-Abschnitte: „Disks / Parität“ und „SMART (alle Disks)“.

## [2.0.0] – 2026-11-11

### Added

- **Parity-Monitoring** (Array I/O): liest `parity` und `parity2` aus `disks.ini` (`numErrors`, Status, Temp).
- **SMART der Parity-Disk(s)**: Health, Temperatur, Reallocated / Pending / Offline Uncorrectable / CRC.
- **Fehler-Deltas**: Vergleich mit `data/state/` – Alarm wenn I/O- oder SMART-Werte seit dem letzten Lauf steigen (erster Lauf = Baseline).
- Report/Mail/Pushover-Abschnitte „Parity“ und „SMART“; CSV `parity.csv` + `smart_YYYY-MM-DD.csv`.
- Config: `USHM_ARRAY_ENABLED`, `USHM_SMART_ENABLED`, `SMART_SCOPE=parity|all`, Schwellwerte.

### Notes

- `SMART_SCOPE=parity` (Default) weckt nicht alle Array-Disks; Standby-Disks werden übersprungen (`smartctl -n standby`).
- Spätere zweite Parity-Disk (`parity2`) wird automatisch mitüberwacht.

## [1.0.6] – 2026-08-03

### Fixed

- Cache misst **nur** Kernel-`statvfs` / System-`df` (nie Btrfs „Device size“ = Summe beider RAID1-SSDs → fälschlich ~1.8 TB).
- Log zeigt Mess-**Quelle** (`statvfs`/`df`) und VERSION zur Kontrolle.

### Docs

- Installation/Update: **kein** `git pull` im `/boot`-Ordner; immer `git clone` HTTPS nach `/tmp` + `install.sh`.
- Cache-Pfad, RAID1, Fehler `Permission denied (publickey)` dokumentiert.

## [1.0.5] – 2026-08-03

### Fixed

- Btrfs **RAID1**-Cache: nutzbare Größe statt Summe beider Disks (~932 GB / ~1 TB statt ~1.8 TB).
- Messung primär über System-`df` (wie `df -hT`); Btrfs-Fallback teilt `Device size` durch **Data ratio**.

## [1.0.4] – 2026-08-03

### Fixed

- Cache-Pfad **case-insensitive** (`/mnt/Cacheintern` → `/mnt/cacheintern`); vermeidet „0 frei von 0“.
- Messung primär über Mount/`df`/`btrfs` (wie `df -hT`), Fallback `disks.ini`.
- Expliziter `CACHE_PATH` hat Vorrang vor automatischer Pool-Wahl.

## [1.0.3] – 2026-08-03

### Fixed

- Cache-Freispeicher nutzt Unraid **`disks.ini`** (gleiche Quelle wie Main-Tab: z. B. ~796 GB frei), nicht nur `df`/`btrfs` auf einem evtl. falschen ~30‑GB-Mount.
- Automatische Wahl des Cache-Pools (`type=Cache`); Warnung wenn `CACHE_PATH` nicht zum WebGUI-Pool passt.
- Report/Log zeigt freigegebenen Pool-Namen.

## [1.0.2] – 2026-08-03

### Fixed

- Cache-SSD auf Unraid: Größen kommen zuerst aus `btrfs filesystem usage` (echte Pool-Größe der 1‑TB-SSD), nicht mehr nur aus oft irreführendem `df`.
- Report zeigt weiterhin **„X frei von Y (Z% belegt)“**.

## [1.0.1] – 2026-08-03

### Fixed

- Cache-SSD-Freispeicher: `df`-Parsing war fehleranfällig (umbrüche, inkonsistente Available vs. Use%).
- Freier Platz und Belegung werden nun aus `Total`/`Used` konsistent berechnet.
- Report/Mail zeigt **„X frei von Y (Z% belegt)“** statt isolierter, potenziell irreführender Werte.

## [1.0.0] – 2026-07-28

### Added

- Initiale modulare Architektur (`ushm.sh` + `lib/` + `modules/`)
- Cache-SSD Monitoring mit Warn-/Kritisch-Schwellwerten (freier %)
- Docker Image Belegung, Writable Layer, Container-Logs
- AppData Top-N + Wachstum seit letztem Lauf
- CSV-Historie unter `data/history/`
- Text-Dashboard im Log
- HTML-Mail via msmtp oder Python (SMTP + STARTTLS)
- Pushover mit Prioritäten (Daily / Warn / Crit)
- `config/config.conf.example`
- Installer für Unraid User Scripts Plugin
- Stub-Module für SMART (v2.0), Array (v2.5), HTML-Dashboard (v3.0)
