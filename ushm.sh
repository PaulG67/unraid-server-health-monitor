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

ushm_usage() {
  cat <<EOF
Unraid Server Health Monitor (USHM) v$(cat "${USHM_HOME}/VERSION" 2>/dev/null || echo "?")

Usage: $(basename "$0") [options]

Options:
  -c, --config PATH   Pfad zur config.conf
  -n, --dry-run       Keine Mails/Pushover senden
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

ushm_run() {
  ushm_info "=== USHM v$(cat "${USHM_HOME}/VERSION") start ==="
  ushm_load_config

  # Checks (Reihenfolge wichtig: AppData vor Growth)
  ushm_check_cache || true
  ushm_check_docker || true
  ushm_check_appdata || true
  ushm_check_growth || true

  # Optionale Module
  if declare -F ushm_check_smart >/dev/null; then
    ushm_check_smart || true
  fi
  if declare -F ushm_check_array >/dev/null; then
    ushm_check_array || true
  fi

  ushm_history_write
  echo
  ushm_print_dashboard
  echo

  if declare -F ushm_write_html_dashboard >/dev/null; then
    ushm_write_html_dashboard || true
  fi

  ushm_dispatch_alerts

  ushm_info "=== USHM fertig (Status: $(ushm_severity_label)) ==="
  return "$USHM_SEVERITY"
}

main() {
  ushm_parse_args "$@"
  ushm_run
}

main "$@"
