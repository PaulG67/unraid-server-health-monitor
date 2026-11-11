#!/usr/bin/env bash
# Konfiguration laden und Defaults setzen
# shellcheck disable=SC2034

ushm_config_defaults() {
  CACHE_PATH="${CACHE_PATH:-/mnt/cache}"
  APPDATA_PATH="${APPDATA_PATH:-/mnt/user/appdata}"
  DOCKER_PATH="${DOCKER_PATH:-/var/lib/docker}"
  TOP_N="${TOP_N:-20}"

  MAIL_ENABLED="${MAIL_ENABLED:-false}"
  SMTP_SERVER="${SMTP_SERVER:-}"
  SMTP_PORT="${SMTP_PORT:-587}"
  SMTP_USER="${SMTP_USER:-}"
  SMTP_PASS="${SMTP_PASS:-}"
  SMTP_TLS="${SMTP_TLS:-true}"
  SMTP_SSL="${SMTP_SSL:-false}"
  SMTP_TIMEOUT="${SMTP_TIMEOUT:-60}"
  SMTP_RETRIES="${SMTP_RETRIES:-3}"
  MAIL_FROM="${MAIL_FROM:-}"
  MAIL_TO="${MAIL_TO:-}"
  MAIL_ON="${MAIL_ON:-daily}"

  PUSHOVER_ENABLED="${PUSHOVER_ENABLED:-false}"
  PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"
  PUSHOVER_USER="${PUSHOVER_USER:-}"
  PUSHOVER_DAILY="${PUSHOVER_DAILY:-true}"

  CACHE_WARN="${CACHE_WARN:-20}"
  CACHE_CRIT="${CACHE_CRIT:-10}"
  DOCKER_WARN="${DOCKER_WARN:-70}"
  DOCKER_CRIT="${DOCKER_CRIT:-90}"
  APP_WARN_MB="${APP_WARN_MB:-500}"
  APP_CRIT_MB="${APP_CRIT_MB:-2000}"
  LOG_WARN_MB="${LOG_WARN_MB:-500}"
  LOG_CRIT_MB="${LOG_CRIT_MB:-2000}"
  DOCKER_LAYER_WARN="${DOCKER_LAYER_WARN:-0}"
  DOCKER_LAYER_CRIT="${DOCKER_LAYER_CRIT:-0}"
  SMART_WARN="${SMART_WARN:-55}"
  SMART_CRIT="${SMART_CRIT:-65}"
  SSD_LIFE_WARN="${SSD_LIFE_WARN:-20}"
  SSD_LIFE_CRIT="${SSD_LIFE_CRIT:-10}"

  # Disk-Inventar / Array / SMART (v2.1)
  USHM_INVENTORY_ENABLED="${USHM_INVENTORY_ENABLED:-true}"
  USHM_ARRAY_ENABLED="${USHM_ARRAY_ENABLED:-true}"
  USHM_SMART_ENABLED="${USHM_SMART_ENABLED:-true}"
  SMART_SCOPE="${SMART_SCOPE:-all}"
  PARITY_ERROR_WARN="${PARITY_ERROR_WARN:-1}"
  PARITY_ERROR_CRIT="${PARITY_ERROR_CRIT:-1}"
  DISK_ERROR_WARN="${DISK_ERROR_WARN:-${PARITY_ERROR_WARN}}"
  DISK_ERROR_CRIT="${DISK_ERROR_CRIT:-${PARITY_ERROR_CRIT}}"
  SMART_REALLOC_WARN="${SMART_REALLOC_WARN:-1}"
  SMART_PENDING_WARN="${SMART_PENDING_WARN:-1}"
  SMART_UNCORR_WARN="${SMART_UNCORR_WARN:-1}"
  SMART_CRC_WARN="${SMART_CRC_WARN:-10}"
  SMART_DELTA_ALERT="${SMART_DELTA_ALERT:-true}"

  DRY_RUN="${DRY_RUN:-false}"
  LOG_LEVEL="${LOG_LEVEL:-info}"
}

ushm_find_config() {
  local candidates=(
    "${USHM_CONFIG:-}"
    "${USHM_HOME}/config/config.conf"
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/config.conf"
    "/boot/config/plugins/user.scripts/scripts/Unraid-Server-Health-Monitor/config/config.conf"
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -n "$c" && -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

ushm_load_config() {
  local cfg
  if ! cfg=$(ushm_find_config); then
    ushm_warn "Keine config.conf gefunden – verwende Defaults"
    ushm_config_defaults
    return 0
  fi

  ushm_info "Lade Konfiguration: $cfg"
  # shellcheck disable=SC1090
  set -a
  # Nur KEY=VALUE Zeilen, Kommentare ignorieren
  # shellcheck source=/dev/null
  source <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$cfg" || true)
  set +a

  ushm_config_defaults

  # DATA_DIR ableiten
  if [[ -z "${DATA_DIR:-}" ]]; then
    DATA_DIR="${USHM_HOME}/data"
  fi
  ushm_mkdir_p "$DATA_DIR"
  ushm_mkdir_p "$DATA_DIR/history"
  ushm_mkdir_p "$DATA_DIR/state"

  USHM_CONFIG_LOADED="$cfg"
}
