#!/usr/bin/env bash
# Cache-SSD / Cache-Pool Monitoring
# shellcheck disable=SC2034

# Ergebnisvariablen:
# CACHE_OK CACHE_TOTAL CACHE_USED CACHE_AVAIL CACHE_PCT_USED CACHE_PCT_FREE CACHE_BAR
# CACHE_POOL_NAME CACHE_PATH_RESOLVED CACHE_SOURCE

# Löst CACHE_PATH auf den echten Mount unter /mnt (case-insensitive).
ushm_resolve_cache_path() {
  local path="${1:-${CACHE_PATH:-/mnt/cache}}"
  local prefer fixed pool sec
  prefer=$(basename "$path")

  if fixed=$(ushm_find_mnt_casefold "$path" 2>/dev/null); then
    CACHE_POOL_NAME=$(basename "$fixed")
    if [[ "$path" != "$fixed" ]]; then
      ushm_warn "CACHE_PATH=$path → $fixed (Linux: Groß/Kleinschreibung)"
    fi
    echo "$fixed"
    return 0
  fi

  if [[ -f /var/local/emhttp/disks.ini ]]; then
    if sec=$(ushm_unraid_find_section "$prefer" 2>/dev/null); then
      CACHE_POOL_NAME="$sec"
      if fixed=$(ushm_find_mnt_casefold "/mnt/$sec" 2>/dev/null); then
        echo "$fixed"
        return 0
      fi
      echo "/mnt/$sec"
      return 0
    fi
    if pool=$(ushm_unraid_pick_cache_pool "$prefer" 2>/dev/null); then
      ushm_warn "CACHE_PATH=$path → Pool '$pool' (disks.ini)"
      CACHE_POOL_NAME="$pool"
      if fixed=$(ushm_find_mnt_casefold "/mnt/$pool" 2>/dev/null); then
        echo "$fixed"
        return 0
      fi
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
  CACHE_SOURCE=""

  local path
  path=$(ushm_resolve_cache_path "${CACHE_PATH:-/mnt/cache}")
  CACHE_PATH_RESOLVED="$path"
  ushm_info "Prüfe Cache: $path${CACHE_POOL_NAME:+ (Pool: $CACHE_POOL_NAME)}"

  # NUR Kernel/statvfs oder System-df – niemals Btrfs Device-size-Summe (RAID1 = 2×)
  if [[ ! -e "$path" ]]; then
    ushm_add_alert 2 "Cache" "Cache-Pfad fehlt: ${CACHE_PATH:-?} → $path (z.B. /mnt/cacheintern)"
    CACHE_BAR="──────────── n/a"
    return 1
  fi

  if ushm_statvfs "$path"; then
    :
  elif ushm_df_system "$path"; then
    :
  else
    ushm_add_alert 2 "Cache" "Cache nicht messbar: $path (statvfs/df fehlgeschlagen)"
    CACHE_BAR="──────────── n/a"
    return 1
  fi

  CACHE_OK=1
  CACHE_TOTAL=$DF_TOTAL
  CACHE_USED=$DF_USED
  CACHE_AVAIL=$DF_AVAIL
  CACHE_PCT_USED=$DF_PCT
  CACHE_SOURCE="${DF_SOURCE:-?}"

  if (( CACHE_TOTAL > 0 )); then
    CACHE_PCT_FREE=$(( CACHE_AVAIL * 100 / CACHE_TOTAL ))
  else
    CACHE_PCT_FREE=$(( 100 - CACHE_PCT_USED ))
  fi
  (( CACHE_PCT_FREE < 0 )) && CACHE_PCT_FREE=0
  (( CACHE_PCT_FREE > 100 )) && CACHE_PCT_FREE=100
  CACHE_BAR="$(ushm_pct_bar "$CACHE_PCT_USED")"

  ushm_info "Cache: $(ushm_bytes_human "$CACHE_AVAIL") frei von $(ushm_bytes_human "$CACHE_TOTAL") (${CACHE_PCT_USED}% belegt, Quelle: ${CACHE_SOURCE})"

  # Warnung wenn weiter ~2× einer 1TB-SSD (RAID1-Bug-Rest)
  if (( CACHE_TOTAL > 1500000000000 )); then
    ushm_warn "Cache-Total $(ushm_bytes_human "$CACHE_TOTAL") wirkt wie 2× SSD-Summe. Prüfe: df -hT $path  und  cat VERSION"
  fi

  if (( CACHE_PCT_FREE < CACHE_CRIT )); then
    ushm_add_alert 2 "Cache" "Nur noch ${CACHE_PCT_FREE}% frei ($(ushm_bytes_human "$CACHE_AVAIL") von $(ushm_bytes_human "$CACHE_TOTAL")) – Schwellwert kritisch <${CACHE_CRIT}%"
  elif (( CACHE_PCT_FREE < CACHE_WARN )); then
    ushm_add_alert 1 "Cache" "Nur noch ${CACHE_PCT_FREE}% frei ($(ushm_bytes_human "$CACHE_AVAIL") von $(ushm_bytes_human "$CACHE_TOTAL")) – Schwellwert Warnung <${CACHE_WARN}%"
  fi

  return 0
}
