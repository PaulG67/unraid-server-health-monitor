# Changelog

Alle wesentlichen Änderungen an USHM werden hier dokumentiert.

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
