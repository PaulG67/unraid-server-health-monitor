#!/usr/bin/env bash
# Cache-SSD / Cache-Pool Monitoring
# shellcheck disable=SC2034

# Ergebnisvariablen:
# CACHE_OK CACHE_TOTAL CACHE_USED CACHE_AVAIL CACHE_PCT_USED CACHE_PCT_FREE CACHE_BAR

ushm_check_cache() {
  CACHE_OK=0
  CACHE_TOTAL=0
  CACHE_USED=0
  CACHE_AVAIL=0
  CACHE_PCT_USED=0
  CACHE_PCT_FREE=0
  CACHE_BAR=""

  local path="${CACHE_PATH:-/mnt/cache}"
  ushm_info "Prüfe Cache: $path"

  if [[ ! -e "$path" ]]; then
    ushm_add_alert 2 "Cache" "Cache-Pfad nicht gefunden: $path"
    CACHE_BAR="──────────── n/a"
    return 1
  fi

  if ! ushm_df "$path"; then
    ushm_add_alert 2 "Cache" "df fehlgeschlagen für $path"
    return 1
  fi

  CACHE_OK=1
  CACHE_TOTAL=$DF_TOTAL
  CACHE_USED=$DF_USED
  CACHE_AVAIL=$DF_AVAIL
  CACHE_PCT_USED=$DF_PCT
  CACHE_PCT_FREE=$(( 100 - CACHE_PCT_USED ))
  CACHE_BAR="$(ushm_pct_bar "$CACHE_PCT_USED")"

  ushm_debug "Cache: used=${CACHE_PCT_USED}% free=${CACHE_PCT_FREE}% avail=$(ushm_bytes_human "$CACHE_AVAIL")"

  if (( CACHE_PCT_FREE < CACHE_CRIT )); then
    ushm_add_alert 2 "Cache" "Nur noch ${CACHE_PCT_FREE}% frei ($(ushm_bytes_human "$CACHE_AVAIL")) – Schwellwert kritisch <${CACHE_CRIT}%"
  elif (( CACHE_PCT_FREE < CACHE_WARN )); then
    ushm_add_alert 1 "Cache" "Nur noch ${CACHE_PCT_FREE}% frei ($(ushm_bytes_human "$CACHE_AVAIL")) – Schwellwert Warnung <${CACHE_WARN}%"
  fi

  return 0
}
