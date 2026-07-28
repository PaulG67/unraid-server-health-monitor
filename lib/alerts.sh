#!/usr/bin/env bash
# Alarm-Auswertung und Versand-Orchestrierung
# shellcheck disable=SC2034

ushm_should_notify_mail() {
  ushm_is_true "$MAIL_ENABLED" || return 1
  case "${MAIL_ON,,}" in
    always|daily) return 0 ;;
    warn)  (( USHM_SEVERITY >= 1 )) && return 0; return 1 ;;
    crit|critical) (( USHM_SEVERITY >= 2 )) && return 0; return 1 ;;
    *) (( USHM_SEVERITY >= 1 )) && return 0; return 1 ;;
  esac
}

ushm_should_notify_pushover() {
  ushm_is_true "$PUSHOVER_ENABLED" || return 1
  if (( USHM_SEVERITY >= 1 )); then
    return 0
  fi
  ushm_is_true "$PUSHOVER_DAILY" && return 0
  return 1
}

ushm_dispatch_alerts() {
  if ushm_is_true "$DRY_RUN"; then
    ushm_info "DRY_RUN aktiv – keine Benachrichtigungen"
    return 0
  fi

  if ushm_should_notify_mail; then
    ushm_send_mail || ushm_error "Mail-Versand fehlgeschlagen"
  else
    if ushm_is_true "$MAIL_ENABLED"; then
      ushm_info "Mail übersprungen (Status=$(ushm_severity_label), MAIL_ON=${MAIL_ON} – bei OK z.B. MAIL_ON=daily setzen)"
    else
      ushm_debug "Mail nicht gesendet (MAIL_ENABLED=false)"
    fi
  fi

  if ushm_should_notify_pushover; then
    ushm_send_pushover || ushm_error "Pushover-Versand fehlgeschlagen"
  else
    ushm_debug "Pushover nicht gesendet"
  fi
}
