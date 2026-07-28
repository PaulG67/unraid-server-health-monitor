# USHM Roadmap

## v1.0 – Foundation (aktuell)

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

## v1.5 – Docker Deep Dive

- [ ] Container-Neustarts (Restart Count)
- [ ] Gestoppte Container erkennen
- [ ] Docker Image Größe detailliert (`docker system df`)
- [ ] Writable Layer pro Container
- [ ] Größte Logfiles mit Container-Namen (verbessert)

## v2.0 – SMART

- [ ] Temperatur (Warn/Crit aus config)
- [ ] Wear Level / Remaining Life
- [ ] TBW
- [ ] SMART-Fehler / Reallocated Sectors
- [ ] Integration in Report + Alarme

## v2.5 – Array

- [ ] Parity-Status
- [ ] Disabled Disks
- [ ] Read Errors / Write Errors
- [ ] Rebuild-Fortschritt
- [ ] emhttp / mdcmd Integration

## v3.0 – HTML Dashboard

- [ ] Persistentes Dashboard unter `data/dashboard.html`
- [ ] Optional über nginx/Unraid WebUI erreichbar
- [ ] Diagramme aus CSV-Historie (z.B. Chart.js offline)
- [ ] Dark Theme wie im Mail-Report
