#!/usr/bin/env bash
# Cache-SSD / Cache-Pool Monitoring
# shellcheck disable=SC2034

# Ergebnisvariablen:
# CACHE_OK CACHE_TOTAL CACHE_USED CACHE_AVAIL CACHE_PCT_USED CACHE_PCT_FREE CACHE_BAR
# CACHE_POOL_NAME CACHE_PATH_RESOLVED

# Löst den echten Unraid-Cache-Pool auf (Name wie im Main-Tab).
# Viele Setups haben z.B. /mnt/cache klein, während der große Pool anders heißt.
ushm_resolve_cache_path() {
  local path="${1:-${CACHE_PATH:-/mnt/cache}}"
  local prefer
  prefer=$(basename "$path")

  if [[ -f /var/local/emhttp/disks.ini ]]; then
    local pool
    if pool=$(ushm_unraid_pick_cache_pool "$prefer" 2>/dev/null); then
      if [[ "$prefer" != "$pool" ]]; then
        ushm_warn "CACHE_PATH=$path → Pool '$pool' (wie Unraid Main / disks.ini)"
      fi
      CACHE_POOL_NAME="$pool"
      echo "/mnt/$pool"
      return 0
    fi
  fi

  CACHE_POOL_NAME="$prefer"
  echo "$path"
}

ushm_check_cache() {
  CACHE_OK=0
  CACHE_TOTAL=0
  CACHE_USED=0
  CACHE_AVAIL=0
  CACHE_PCT_USED=0
  CACHE_PCT_FREE=0
  CACHE_BAR=""
  CACHE_POOL_NAME=""
  CACHE_PATH_RESOLVED=""

  local path
  path=$(ushm_resolve_cache_path "${CACHE_PATH:-/mnt/cache}")
  CACHE_PATH_RESOLVED="$path"
  ushm_info "Prüfe Cache: $path${CACHE_POOL_NAME:+ (Pool: $CACHE_POOL_NAME)}"

  # 1) Unraid disks.ini – gleiche Free/Size-Werte wie Main-Tab
  if [[ -n "${CACHE_POOL_NAME:-}" ]] && ushm_unraid_disk_stats "$CACHE_POOL_NAME"; then
    DF_TOTAL=$UNRAID_FS_TOTAL
    DF_USED=$UNRAID_FS_USED
    DF_AVAIL=$UNRAID_FS_FREE
    DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
    (( DF_PCT < 0 )) && DF_PCT=0
    (( DF_PCT > 100 )) && DF_PCT=100
    ushm_debug "Cache via disks.ini [$CACHE_POOL_NAME]: free=$(ushm_bytes_human "$DF_AVAIL") of $(ushm_bytes_human "$DF_TOTAL")"
  elif [[ -e "$path" ]] && ushm_df "$path" "yes"; then
    :
  elif [[ -e "$path" ]] && ushm_df "$path" "no"; then
    :
  else
    ushm_add_alert 2 "Cache" "Cache-Pfad/Pool nicht messbar: $path (CACHE_PATH prüfen)"
    CACHE_BAR="──────────── n/a"
    return 1
  fi

  CACHE_OK=1
  CACHE_TOTAL=$DF_TOTAL
  CACHE_USED=$DF_USED
  CACHE_AVAIL=$DF_AVAIL
  CACHE_PCT_USED=$DF_PCT
  if (( CACHE_TOTAL > 0 )); then
    CACHE_PCT_FREE=$(( CACHE_AVAIL * 100 / CACHE_TOTAL ))
  else
    CACHE_PCT_FREE=$(( 100 - CACHE_PCT_USED ))
  fi
  (( CACHE_PCT_FREE < 0 )) && CACHE_PCT_FREE=0
  (( CACHE_PCT_FREE > 100 )) && CACHE_PCT_FREE=100
  CACHE_BAR="$(ushm_pct_bar "$CACHE_PCT_USED")"

  ushm_info "Cache: $(ushm_bytes_human "$CACHE_AVAIL") frei von $(ushm_bytes_human "$CACHE_TOTAL") (${CACHE_PCT_USED}% belegt / ${CACHE_PCT_FREE}% frei)"

  # Sanity: wenn df/btrfs ~30 GB meldet, WebGUI aber TB-Pool hat – Hinweis
  if (( CACHE_TOTAL > 0 && CACHE_TOTAL < 100000000000 )); then
    ushm_warn "Cache-Gesamtgröße wirkt klein ($(ushm_bytes_human "$CACHE_TOTAL")). In config.conf CACHE_PATH auf den Pool aus Main setzen (z.B. /mnt/cache_nvme)."
  fi

  if (( CACHE_PCT_FREE < CACHE_CRIT )); then
    ushm_add_alert 2 "Cache" "Nur noch ${CACHE_PCT_FREE}% frei ($(ushm_bytes_human "$CACHE_AVAIL") von $(ushm_bytes_human "$CACHE_TOTAL")) – Schwellwert kritisch <${CACHE_CRIT}%"
  elif (( CACHE_PCT_FREE < CACHE_WARN )); then
    ushm_add_alert 1 "Cache" "Nur noch ${CACHE_PCT_FREE}% frei ($(ushm_bytes_human "$CACHE_AVAIL") von $(ushm_bytes_human "$CACHE_TOTAL")) – Schwellwert Warnung <${CACHE_WARN}%"
  fi

  return 0
}
