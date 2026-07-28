#!/usr/bin/env bash
# =============================================================================
# USHM Installer – richtet User Scripts Ordner auf Unraid ein
# Auf dem Unraid-Server ausführen (als root).
# =============================================================================
set -euo pipefail

SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_BASE="/boot/config/plugins/user.scripts/scripts"
TARGET_NAME="Unraid-Server-Health-Monitor"
TARGET="${TARGET_BASE}/${TARGET_NAME}"

echo "========================================="
echo " USHM Installer"
echo "========================================="
echo
echo "Quelle : $SCRIPT_SRC"
echo "Ziel   : $TARGET"
echo

if [[ ! -d "/boot/config" ]]; then
  echo "FEHLER: /boot/config nicht gefunden."
  echo "Dieser Installer muss auf einem Unraid-Server laufen."
  exit 1
fi

if [[ ! -d "$TARGET_BASE" ]]; then
  echo "User Scripts Plugin-Pfad fehlt – lege an: $TARGET_BASE"
  mkdir -p "$TARGET_BASE"
fi

mkdir -p "$TARGET"
mkdir -p "$TARGET/lib"
mkdir -p "$TARGET/modules"
mkdir -p "$TARGET/config"
mkdir -p "$TARGET/data/history"
mkdir -p "$TARGET/data/state"
mkdir -p "$TARGET/docs"

# Dateien kopieren (config.conf nicht überschreiben falls vorhanden)
rsync -a --exclude 'data/' --exclude '.git/' --exclude 'config/config.conf' \
  "$SCRIPT_SRC/" "$TARGET/"

if [[ ! -f "$TARGET/config/config.conf" ]]; then
  cp "$TARGET/config/config.conf.example" "$TARGET/config/config.conf"
  echo "→ config.conf aus Example erstellt"
else
  echo "→ bestehende config.conf belassen"
fi

# User Scripts erwartet oft eine Datei namens "script"
cat >"$TARGET/script" <<'EOF'
#!/bin/bash
# User Scripts Wrapper für Unraid Server Health Monitor
DIR="$(dirname "$(readlink -f "$0")")"
exec bash "${DIR}/ushm.sh" "$@"
EOF
chmod +x "$TARGET/script"
chmod +x "$TARGET/ushm.sh"
chmod +x "$TARGET/install.sh" 2>/dev/null || true

# Beschreibung für User Scripts UI
echo "Unraid Server Health Monitor – Cache, Docker, AppData, Alarme" >"$TARGET/description"

echo
echo "Installation abgeschlossen."
echo
echo "Nächste Schritte:"
echo "  1. Konfiguration bearbeiten:"
echo "     nano ${TARGET}/config/config.conf"
echo
echo "  2. In Unraid → Settings → User Scripts den Eintrag"
echo "     '${TARGET_NAME}' planen (z.B. täglich)."
echo
echo "  3. Testlauf:"
echo "     bash ${TARGET}/ushm.sh --dry-run"
echo
echo "========================================="
