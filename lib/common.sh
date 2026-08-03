#!/usr/bin/env bash
# Unraid Server Health Monitor – gemeinsame Hilfsfunktionen
# shellcheck disable=SC2034

set -o pipefail

# ---------------------------------------------------------------------------
# Farben / Symbole (für Terminal & Log; HTML nutzt eigene Markup)
# ---------------------------------------------------------------------------
USHM_OK="✓"
USHM_WARN="⚠"
USHM_CRIT="✗"
USHM_INFO="•"

USHM_GREEN="🟢"
USHM_YELLOW="🟡"
USHM_RED="🔴"

# Globale Statusstufe: 0=ok, 1=warn, 2=crit
USHM_SEVERITY=0

# Alarm-Einträge: "stufe|kategorie|nachricht"
declare -a USHM_ALERTS=()

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
ushm_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local want="${LOG_LEVEL:-info}"

  case "$want" in
    debug) ;;
    info)  [[ "$level" == "debug" ]] && return 0 ;;
    warn)  [[ "$level" =~ ^(debug|info)$ ]] && return 0 ;;
    error) [[ "$level" != "error" ]] && return 0 ;;
  esac

  # Sofort ausgeben (wichtig bei langen du-Scans)
  printf '[%s] %-5s %s\n' "$ts" "${level^^}" "$msg" >&2
}

ushm_debug() { ushm_log debug "$*"; }
ushm_info()  { ushm_log info  "$*"; }
ushm_warn()  { ushm_log warn  "$*"; }
ushm_error() { ushm_log error "$*"; }

# ---------------------------------------------------------------------------
# Severity / Alerts
# ---------------------------------------------------------------------------
ushm_raise_severity() {
  local s="$1"
  (( s > USHM_SEVERITY )) && USHM_SEVERITY=$s
}

ushm_add_alert() {
  # $1 = 1(warn)|2(crit), $2 = kategorie, $3 = nachricht
  local level="$1" cat="$2" msg="$3"
  USHM_ALERTS+=("${level}|${cat}|${msg}")
  ushm_raise_severity "$level"
  if (( level >= 2 )); then
    ushm_error "[$cat] $msg"
  else
    ushm_warn  "[$cat] $msg"
  fi
}

ushm_severity_label() {
  case "${1:-$USHM_SEVERITY}" in
    0) echo "OK" ;;
    1) echo "WARNUNG" ;;
    2) echo "KRITISCH" ;;
    *) echo "UNBEKANNT" ;;
  esac
}

ushm_severity_emoji() {
  case "${1:-$USHM_SEVERITY}" in
    0) echo "$USHM_GREEN" ;;
    1) echo "$USHM_YELLOW" ;;
    2) echo "$USHM_RED" ;;
    *) echo "$USHM_INFO" ;;
  esac
}

# ---------------------------------------------------------------------------
# Zahlen / Formatierung
# ---------------------------------------------------------------------------
ushm_bytes_human() {
  # Eingabe: Bytes (Integer)
  local b="${1:-0}"
  awk -v b="$b" 'BEGIN {
    split("B KB MB GB TB PB", u, " ")
    i = 1
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]
    else printf "%.1f %s", b, u[i]
  }'
}

ushm_mb_to_bytes() {
  local mb="${1:-0}"
  echo $(( mb * 1024 * 1024 ))
}

ushm_bytes_to_mb() {
  local b="${1:-0}"
  echo $(( b / 1024 / 1024 ))
}

ushm_pct_bar() {
  # $1 = Prozent 0-100, $2 = Breite (default 12)
  local pct="${1:-0}" width="${2:-12}"
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local filled empty i
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  local bar=""
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty; i++ )); do bar+="░"; done
  printf '%s %3d %%' "$bar" "$pct"
}

ushm_is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

ushm_require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      ushm_error "Benötigtes Kommando fehlt: $c"
      return 1
    }
  done
}

ushm_hostname() {
  hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unraid"
}

ushm_mkdir_p() {
  mkdir -p "$1" 2>/dev/null || {
    ushm_error "Kann Verzeichnis nicht anlegen: $1"
    return 1
  }
}

# Directory size in bytes (du -sb preferred, fallback -sk)
ushm_dir_size_bytes() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  local out
  if out=$(du -sb "$path" 2>/dev/null | awk '{print $1}'); then
    echo "${out:-0}"
  else
    out=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
    echo $(( ${out:-0} * 1024 ))
  fi
}

# ---------------------------------------------------------------------------
# Btrfs-Pool-Größen (Unraid Cache oft btrfs; df allein ist irreführend)
# Setzt: BTRFS_TOTAL BTRFS_USED BTRFS_FREE  (Bytes), return 0 bei Erfolg
# ---------------------------------------------------------------------------
ushm_btrfs_usage() {
  local path="$1"
  BTRFS_TOTAL=0; BTRFS_USED=0; BTRFS_FREE=0
  command -v btrfs >/dev/null 2>&1 || return 1
  [[ -e "$path" ]] || return 1

  local raw
  raw=$(btrfs filesystem usage -b "$path" 2>/dev/null) || return 1
  [[ -n "$raw" ]] || return 1

  # Zeilen z.B. "    Device size:             1000204886016"
  BTRFS_TOTAL=$(awk '
    /Device size:/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
    }' <<<"$raw")
  BTRFS_USED=$(awk '
    /^[[:space:]]*Used:/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
    }' <<<"$raw")
  # Free (estimated): bevorzugen – entspricht dem nutzbaren freien Platz im Pool
  BTRFS_FREE=$(awk '
    /Free \(estimated\):/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
    }' <<<"$raw")
  # Fallback: Free (statfs, df)
  if [[ -z "$BTRFS_FREE" || "$BTRFS_FREE" == "0" ]]; then
    BTRFS_FREE=$(awk '
      /Free \(statfs, df\):/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
      }' <<<"$raw")
  fi

  [[ "$BTRFS_TOTAL" =~ ^[0-9]+$ && "$BTRFS_TOTAL" -gt 0 ]] || return 1

  if [[ ! "$BTRFS_USED" =~ ^[0-9]+$ ]]; then
    if [[ "$BTRFS_FREE" =~ ^[0-9]+$ ]]; then
      BTRFS_USED=$(( BTRFS_TOTAL - BTRFS_FREE ))
      (( BTRFS_USED < 0 )) && BTRFS_USED=0
    else
      return 1
    fi
  fi
  if [[ ! "$BTRFS_FREE" =~ ^[0-9]+$ ]]; then
    BTRFS_FREE=$(( BTRFS_TOTAL - BTRFS_USED ))
    (( BTRFS_FREE < 0 )) && BTRFS_FREE=0
  fi

  return 0
}

# df: total/used/avail bytes + use% für einen Mount
# Setzt: DF_TOTAL DF_USED DF_AVAIL DF_PCT
#
# Reihenfolge:
# 1) btrfs filesystem usage (besser für Unraid-Cache-Pools)
# 2) GNU df -B1 --output=...
# 3) portable df -Pk (letzte Zeile, %-Feld finden)
ushm_df() {
  local path="$1"
  DF_TOTAL=0; DF_USED=0; DF_AVAIL=0; DF_PCT=0
  [[ -e "$path" ]] || return 1

  # --- 1) Btrfs-Pool (Unraid Cache) ---
  local fstype=""
  fstype=$(findmnt -n -o FSTYPE "$path" 2>/dev/null || true)
  if [[ -z "$fstype" ]]; then
    fstype=$(stat -f -c %T "$path" 2>/dev/null || true)
  fi
  if [[ "${fstype,,}" == *btrfs* ]] && ushm_btrfs_usage "$path"; then
    DF_TOTAL=$BTRFS_TOTAL
    DF_USED=$BTRFS_USED
    DF_AVAIL=$BTRFS_FREE
    DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
    (( DF_PCT < 0 )) && DF_PCT=0
    (( DF_PCT > 100 )) && DF_PCT=100
    ushm_debug "df via btrfs: total=$DF_TOTAL used=$DF_USED free=$DF_AVAIL (${DF_PCT}%)"
    return 0
  fi

  local t=0 u=0 a=0 p=0
  local parsed=0

  # --- 2) GNU df Bytes ---
  if command -v df >/dev/null 2>&1; then
    local out
    if out=$(df -B1 --output=size,used,avail,pcent "$path" 2>/dev/null | awk 'NR==2 {print}'); then
      local pc
      read -r t u a pc <<<"$out"
      if [[ -n "$t" && "$t" =~ ^[0-9]+$ && "$t" -gt 0 ]]; then
        p=${pc%%%}
        p=${p// /}
        parsed=1
      fi
    fi
  fi

  # --- 3) Fallback: df -Pk, letzte Datenzeile; Capacity endet auf % ---
  if (( parsed == 0 )); then
    local line
    line=$(df -Pk "$path" 2>/dev/null | awk 'NR>1 { line=$0 } END { print line }')
    [[ -n "$line" ]] || return 1

    local -a f=()
    # shellcheck disable=SC2206
    f=($line)
    local i pct_i=-1
    for (( i=0; i<${#f[@]}; i++ )); do
      if [[ "${f[i]}" == *% ]]; then
        pct_i=$i
        break
      fi
    done
    (( pct_i >= 3 )) || return 1

    t="${f[pct_i-3]}"
    u="${f[pct_i-2]}"
    a="${f[pct_i-1]}"
    p="${f[pct_i]%%%}"
    t=$(( t * 1024 ))
    u=$(( u * 1024 ))
    a=$(( a * 1024 ))
    parsed=1
  fi

  [[ "$t" =~ ^[0-9]+$ && "$u" =~ ^[0-9]+$ ]] || return 1
  (( t > 0 )) || return 1

  DF_TOTAL=$t
  DF_USED=$u

  local free_calc=$(( DF_TOTAL - DF_USED ))
  (( free_calc < 0 )) && free_calc=0

  if [[ "$a" =~ ^[0-9]+$ ]] && (( a > 0 )); then
    local lo hi
    lo=$(( free_calc * 50 / 100 ))
    hi=$(( free_calc * 150 / 100 ))
    if (( free_calc == 0 )) || (( a >= lo && a <= hi )); then
      DF_AVAIL=$a
    else
      DF_AVAIL=$free_calc
    fi
  else
    DF_AVAIL=$free_calc
  fi

  DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
  (( DF_PCT < 0 )) && DF_PCT=0
  (( DF_PCT > 100 )) && DF_PCT=100

  return 0
}
