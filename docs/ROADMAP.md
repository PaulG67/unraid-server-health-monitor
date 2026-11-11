# USHM Roadmap

## v1.0 – Foundation

- [x] Modulare Bash-Architektur
- [x] Cache-SSD Belegung + Schwellwerte
- [x] Docker Image Belegung
- [x] Docker Writable Layer Größe
- [x] Container-Log Größe + Top-Logs
- [x] AppData Top-N Verzeichnisse
- [x] Wachstum seit letztem Lauf
- [x] CSV-Historie
- [x] Text-Dashboard im Log
- [x] HTML-Mail Report
- [x] Pushover mit Prioritäten
- [x] config.conf
- [x] Installer für User Scripts

## v1.x – Cache-Fixes

- [x] Cache-Pfad case-insensitive / Pool-Erkennung
- [x] RAID1 nutzbare Größe (statvfs/df, kein Device-size×2)

## v2.0 – Parity & SMART (aktuell)

- [x] Parity I/O-Fehler (`numErrors`) aus disks.ini
- [x] Parity Status (disabled / rot)
- [x] Parity-Sync-Fehler (`sbSyncErrs`)
- [x] Automatisch `parity` + `parity2`
- [x] SMART Health / Temperatur
- [x] Reallocated / Pending / Uncorrectable / CRC
- [x] Deltas seit letztem Lauf + Alarme
- [x] Integration Report + Historie
- [ ] SMART Wear Level / Remaining Life / TBW (optional)
- [ ] SMART_SCOPE=all als Default-Empfehlung dokumentieren (optional)

## v1.5 – Docker Deep Dive

- [ ] Container-Neustarts (Restart Count)
- [ ] Gestoppte Container erkennen
- [ ] Docker Image Größe detailliert (`docker system df`)
- [ ] Writable Layer pro Container

## v2.5 – Array (erweitert)

- [ ] Disabled Data-Disks
- [ ] Read/Write-Fehler aller Array-Disks
- [ ] Rebuild-Fortschritt detailliert
- [ ] mdcmd Integration

## v3.0 – HTML Dashboard

- [ ] Persistentes Dashboard unter `data/dashboard.html`
- [ ] Optional über nginx/Unraid WebUI erreichbar
- [ ] Diagramme aus CSV-Historie
- [ ] Dark Theme wie im Mail-Report
