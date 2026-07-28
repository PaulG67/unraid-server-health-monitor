#!/usr/bin/env bash
# Pushover Benachrichtigungen mit Prioritäten
# shellcheck disable=SC2034

ushm_send_pushover() {
  [[ -n "$PUSHOVER_TOKEN" && -n "$PUSHOVER_USER" ]] || {
    ushm_warn "Pushover: TOKEN/USER fehlen"
    return 1
  }

  command -v curl >/dev/null 2>&1 || {
    ushm_error "curl fehlt – Pushover nicht möglich"
    return 1
  }

  local host title message priority sound
  host="$(ushm_hostname)"
  local emoji
  emoji="$(ushm_severity_emoji)"

  case "$USHM_SEVERITY" in
    2)
      title="${emoji} USHM KRITISCH – ${host}"
      priority=1
      sound="siren"
      ;;
    1)
      title="${emoji} USHM Warnung – ${host}"
      priority=0
      sound="pushover"
      ;;
    *)
      title="${emoji} USHM Daily Report – ${host}"
      priority="-1"
      sound="none"
      ;;
  esac

  message="$(ushm_report_pushover)"

  ushm_info "Sende Pushover: $title (prio=$priority)"

  local resp
  resp=$(curl -sS \
    --form-string "token=${PUSHOVER_TOKEN}" \
    --form-string "user=${PUSHOVER_USER}" \
    --form-string "title=${title}" \
    --form-string "message=${message}" \
    --form-string "priority=${priority}" \
    --form-string "sound=${sound}" \
    https://api.pushover.net/1/messages.json 2>&1) || {
    ushm_error "Pushover curl Fehler: $resp"
    return 1
  }

  if echo "$resp" | grep -q '"status":1'; then
    ushm_info "Pushover OK"
    return 0
  fi

  ushm_error "Pushover Antwort: $resp"
  return 1
}
