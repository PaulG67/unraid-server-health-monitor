#!/usr/bin/env bash
# =============================================================================
# Unraid Server Health Monitor (USHM)
# Main entrypoint – für User Scripts Plugin oder Cron
# =============================================================================
set -euo pipefail

USHM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export USHM_HOME

# shellcheck source=lib/common.sh
source "${USHM_HOME}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${USHM_HOME}/lib/config.sh"
# shellcheck source=lib/cache.sh
source "${USHM_HOME}/lib/cache.sh"
# shellcheck source=lib/docker.sh
source "${USHM_HOME}/lib/docker.sh"
# shellcheck source=lib/appdata.sh
source "${USHM_HOME}/lib/appdata.sh"
# shellcheck source=lib/growth.sh
source "${USHM_HOME}/lib/growth.sh"
# shellcheck source=lib/history.sh
source "${USHM_HOME}/lib/history.sh"
# shellcheck source=lib/report.sh
source "${USHM_HOME}/lib/report.sh"
# shellcheck source=lib/alerts.sh
source "${USHM_HOME}/lib/alerts.sh"
# shellcheck source=lib/mail.sh
source "${USHM_HOME}/lib/mail.sh"
# shellcheck source=lib/pushover.sh
source "${USHM_HOME}/lib/pushover.sh"

# Optionale Module (ab v2.0 / v2.5 / v3.0)
[[ -f "${USHM_HOME}/modules/smart.sh" ]] && source "${USHM_HOME}/modules/smart.sh"
[[ -f "${USHM_HOME}/modules/array.sh" ]] && source "${USHM_HOME}/modules/array.sh"
[[ -f "${USHM_HOME}/modules/dashboard.sh" ]] && source "${USHM_HOME}/modules/dashboard.sh"

USHM_MODE=run

ushm_usage() {
  cat <<EOF
Unraid Server Health Monitor (USHM) v$(cat "${USHM_HOME}/VERSION" 2>/dev/null || echo "?")

Usage: $(basename "$0") [options]

Options:
  -c, --config PATH   Pfad zur config.conf
  -n, --dry-run       Keine Mails/Pushover senden
  -t, --test-notify   Nur Mail + Pushover aus der Config testen
  -q, --quiet         Weniger Log-Ausgabe (LOG_LEVEL=warn)
  -h, --help          Diese Hilfe

Ohne Optionen: vollständiger Health-Check + Report + Historie + Alarme.
EOF
}

ushm_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        export USHM_CONFIG="${2:-}"
        shift 2
        ;;
      -n|--dry-run)
        export DRY_RUN=true
        shift
        ;;
      -t|--test-notify)
        USHM_MODE=test-notify
        shift
        ;;
      -q|--quiet)
        export LOG_LEVEL=warn
        shift
        ;;
      -h|--help)
        ushm_usage
        exit 0
        ;;
      *)
        ushm_error "Unbekannte Option: $1"
        ushm_usage
        exit 1
        ;;
    esac
  done
}

ushm_test_notify() {
  ushm_info "=== USHM Notify-Test ==="
  ushm_load_config
  DRY_RUN=false

  # Minimale Report-Daten, damit Templates nicht leer knallen
  CACHE_BAR="$(ushm_pct_bar 0)"
  CACHE_PCT_USED=0
  CACHE_PCT_FREE=100
  CACHE_AVAIL=0
  DOCKER_BAR="$(ushm_pct_bar 0)"
  DOCKER_PCT=0
  DOCKER_MODE="test"
  DOCKER_USED=0
  DOCKER_TOTAL=0
  DOCKER_LAYER_BYTES=0
  DOCKER_LOG_BYTES=0
  APPDATA_TOTAL_BYTES=0
  APPDATA_TOP="(Notify-Test – kein Scan)"
  GROWTH_TOP="(Notify-Test – kein Scan)"
  APPDATA_NAMES=()
  APPDATA_SIZES=()
  GROWTH_NAMES=()
  GROWTH_DELTAS=()
  USHM_SEVERITY=0
  USHM_ALERTS=()
  ushm_add_alert 1 "Test" "Dies ist ein USHM Notify-Test. Wenn du das siehst, funktioniert der Versand."

  local rc=0

  echo
  ushm_info "--- Mail ---"
  if ! ushm_is_true "$MAIL_ENABLED"; then
    ushm_warn "MAIL_ENABLED=false – Mail-Test übersprungen"
  elif [[ -z "${SMTP_SERVER:-}" || -z "${MAIL_FROM:-}" || -z "${MAIL_TO:-}" ]]; then
    ushm_error "Mail-Config unvollständig (SMTP_SERVER / MAIL_FROM / MAIL_TO)"
    rc=1
  else
    if ushm_send_mail; then
      ushm_info "Mail-Test OK → ${MAIL_TO}"
    else
      ushm_error "Mail-Test FEHLGESCHLAGEN"
      rc=1
    fi
  fi

  echo
  ushm_info "--- Pushover ---"
  if ! ushm_is_true "$PUSHOVER_ENABLED"; then
    ushm_warn "PUSHOVER_ENABLED=false – Pushover-Test übersprungen"
  elif [[ -z "${PUSHOVER_TOKEN:-}" || -z "${PUSHOVER_USER:-}" ]]; then
    ushm_error "Pushover-Config unvollständig (TOKEN / USER)"
    rc=1
  else
    if ushm_send_pushover; then
      ushm_info "Pushover-Test OK"
    else
      ushm_error "Pushover-Test FEHLGESCHLAGEN"
      rc=1
    fi
  fi

  echo
  if (( rc == 0 )); then
    ushm_info "=== Notify-Test fertig ==="
  else
    ushm_error "=== Notify-Test mit Fehlern ==="
  fi
  exit "$rc"
}

ushm_run() {
  ushm_info "=== USHM v$(cat "${USHM_HOME}/VERSION") start ==="
  ushm_load_config

  # Checks (Reihenfolge wichtig: AppData vor Growth)
  ushm_info "[1/5] Cache…"
  ushm_check_cache || true
  ushm_info "[2/5] Docker…"
  ushm_check_docker || true
  ushm_info "[3/5] AppData…"
  ushm_check_appdata || true
  ushm_info "[4/5] Wachstum…"
  ushm_check_growth || true

  # Optionale Module
  if declare -F ushm_check_smart >/dev/null; then
    ushm_check_smart || true
  fi
  if declare -F ushm_check_array >/dev/null; then
    ushm_check_array || true
  fi

  ushm_info "[5/5] Historie + Report…"
  ushm_history_write
  echo
  ushm_print_dashboard
  echo

  if declare -F ushm_write_html_dashboard >/dev/null; then
    ushm_write_html_dashboard || true
  fi

  ushm_dispatch_alerts

  ushm_info "=== USHM fertig (Status: $(ushm_severity_label)) ==="
  # Exit-Code bewusst setzen, ohne set -e auszulösen
  return 0
}

ushm_exit_with_severity() {
  exit "$USHM_SEVERITY"
}

main() {
  ushm_parse_args "$@"
  case "${USHM_MODE}" in
    test-notify) ushm_test_notify ;;
    *)
      ushm_run
      ushm_exit_with_severity
      ;;
  esac
}

main "$@"
