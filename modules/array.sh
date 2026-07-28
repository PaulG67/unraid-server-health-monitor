#!/usr/bin/env bash
# Array Monitoring – geplant für v2.5
# Parity, Disabled Disks, Read/Write Errors, Rebuild
# shellcheck disable=SC2034

USHM_ARRAY_ENABLED="${USHM_ARRAY_ENABLED:-false}"

ushm_check_array() {
  if ! ushm_is_true "$USHM_ARRAY_ENABLED"; then
    ushm_debug "Array-Modul vorhanden, aber deaktiviert (USHM_ARRAY_ENABLED=false) – kommt in v2.5"
    return 0
  fi

  ushm_info "Array-Check (v2.5 Preview)"

  # Unraid mdcmd /var/local/emhttp/var.ini / disks.ini
  if [[ -f /var/local/emhttp/var.ini ]]; then
    ushm_debug "emhttp var.ini gefunden – Parsing folgt in v2.5"
  else
    ushm_debug "Keine emhttp-Daten – nicht auf Unraid?"
  fi
  return 0
}
