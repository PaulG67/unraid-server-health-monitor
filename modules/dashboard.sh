#!/usr/bin/env bash
# HTML Dashboard File – geplant für v3.0
# shellcheck disable=SC2034

USHM_DASHBOARD_ENABLED="${USHM_DASHBOARD_ENABLED:-false}"
USHM_DASHBOARD_PATH="${USHM_DASHBOARD_PATH:-}"

ushm_write_html_dashboard() {
  if ! ushm_is_true "$USHM_DASHBOARD_ENABLED"; then
    ushm_debug "HTML-Dashboard deaktiviert (v3.0)"
    return 0
  fi

  local out="${USHM_DASHBOARD_PATH:-${DATA_DIR}/dashboard.html}"
  ushm_info "Schreibe HTML-Dashboard: $out"
  ushm_report_html >"$out"
  return 0
}
