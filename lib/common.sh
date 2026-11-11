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

# ANSI für kritische Werte im Terminal-Report (HTML: ushm_ansi_to_html)
USHM_C_RED=$'\033[31m'
USHM_C_YEL=$'\033[33m'
USHM_C_RST=$'\033[0m'

# $1=text → rot / gelb (kritisch / Warnung)
ushm_c_red() { printf '%s%s%s' "$USHM_C_RED" "$1" "$USHM_C_RST"; }
ushm_c_yel() { printf '%s%s%s' "$USHM_C_YEL" "$1" "$USHM_C_RST"; }

# ANSI → HTML-Spans (für Mail-Report <pre>)
ushm_ansi_to_html() {
  local s="$1"
  s=${s//$USHM_C_RED/<span style="color:#f87171;font-weight:600">}
  s=${s//$USHM_C_YEL/<span style="color:#fbbf24;font-weight:600">}
  s=${s//$USHM_C_RST/<\/span>}
  printf '%s' "$s"
}

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
# Unraid disks.ini – gleiche Quelle wie WebGUI (Main → Free/Size)
# Setzt: UNRAID_FS_TOTAL UNRAID_FS_USED UNRAID_FS_FREE (Bytes)
# ---------------------------------------------------------------------------
ushm_unraid_ini_get() {
  # $1=ini-file $2=section $3=key → Wert ohne Anführungszeichen
  # Section-Vergleich case-insensitive (Config oft /mnt/Cacheintern, Mount /mnt/cacheintern)
  local file="$1" section="$2" key="$3"
  [[ -f "$file" ]] || return 1
  awk -F= -v sec="$section" -v key="$key" '
    BEGIN { insec=0; secl=tolower(sec) }
    /^\[/ {
      s=$0
      gsub(/^\[|\]$/, "", s)
      insec = (tolower(s) == secl)
      next
    }
    insec && $1 == key {
      val=$0
      sub(/^[^=]*=/, "", val)
      gsub(/\r/, "", val)
      gsub(/^"/, "", val)
      gsub(/"$/, "", val)
      print val
      exit
    }
  ' "$file"
}

# Löst einen Pool-Namen/Path case-insensitive gegen /mnt/* auf.
# Gibt echten Mount-Pfad aus (z.B. /mnt/cacheintern), return 0 bei Treffer.
ushm_find_mnt_casefold() {
  local want="$1"
  local base want_l n n_l
  [[ -n "$want" ]] || return 1
  base=$(basename "$want")
  want_l=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')

  if [[ -d "/mnt/$base" ]]; then
    echo "/mnt/$base"
    return 0
  fi
  if [[ "$want" == /* && -d "$want" ]]; then
    echo "$want"
    return 0
  fi

  local d
  for d in /mnt/*/; do
    [[ -d "$d" ]] || continue
    n=$(basename "$d")
    case "$n" in
      user|disks|remotes|addons|rootshare|disk[0-9]*) continue ;;
    esac
    n_l=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')
    if [[ "$n_l" == "$want_l" ]]; then
      echo "/mnt/$n"
      return 0
    fi
  done
  return 1
}

# Liefert den echten Section-Namen aus disks.ini (korrektes Casing), case-insensitive Suche.
ushm_unraid_find_section() {
  local want="$1"
  local ini="${2:-/var/local/emhttp/disks.ini}"
  [[ -f "$ini" && -n "$want" ]] || return 1
  awk -v want="$want" '
    BEGIN { wl=tolower(want) }
    /^\[/ {
      s=$0
      gsub(/^\[|\]$/, "", s)
      if (tolower(s) == wl) { print s; exit 0 }
    }
  ' "$ini"
}

# Unraid speichert fsSize/fsFree/fsUsed in KiB (WebGUI multipliziert mit 1024).
# Fallback: bereits Bytes, wenn Werte realistisch groß sind (>= 100 GiB als nackte Zahl).
ushm_unraid_fs_to_bytes() {
  local v="${1:-0}"
  [[ "$v" =~ ^[0-9]+$ ]] || { echo 0; return 1; }
  # Bereits Bytes: >= 100 GiB
  if (( v >= 107374182400 )); then
    echo "$v"
    return 0
  fi
  echo $(( v * 1024 ))
}

ushm_unraid_disk_stats() {
  # $1 = Disk-/Pool-Name aus disks.ini (z.B. cache, cache_nvme)
  local name="$1"
  local ini="${2:-/var/local/emhttp/disks.ini}"
  UNRAID_FS_TOTAL=0; UNRAID_FS_USED=0; UNRAID_FS_FREE=0
  [[ -f "$ini" && -n "$name" ]] || return 1

  local size free used
  size=$(ushm_unraid_ini_get "$ini" "$name" "fsSize") || true
  free=$(ushm_unraid_ini_get "$ini" "$name" "fsFree") || true
  used=$(ushm_unraid_ini_get "$ini" "$name" "fsUsed") || true

  [[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 ]] || return 1

  UNRAID_FS_TOTAL=$(ushm_unraid_fs_to_bytes "$size")
  if [[ "$free" =~ ^[0-9]+$ ]]; then
    UNRAID_FS_FREE=$(ushm_unraid_fs_to_bytes "$free")
  fi
  if [[ "$used" =~ ^[0-9]+$ ]]; then
    UNRAID_FS_USED=$(ushm_unraid_fs_to_bytes "$used")
  elif (( UNRAID_FS_TOTAL > 0 && UNRAID_FS_FREE > 0 )); then
    UNRAID_FS_USED=$(( UNRAID_FS_TOTAL - UNRAID_FS_FREE ))
    (( UNRAID_FS_USED < 0 )) && UNRAID_FS_USED=0
  else
    return 1
  fi

  if (( UNRAID_FS_FREE == 0 && UNRAID_FS_TOTAL > 0 && UNRAID_FS_USED > 0 )); then
    UNRAID_FS_FREE=$(( UNRAID_FS_TOTAL - UNRAID_FS_USED ))
    (( UNRAID_FS_FREE < 0 )) && UNRAID_FS_FREE=0
  fi

  (( UNRAID_FS_TOTAL > 0 )) || return 1
  return 0
}

# Listet Cache-Pools aus disks.ini (type=Cache), größter zuerst: "name\tfsSizeKiB"
ushm_unraid_list_cache_pools() {
  local ini="${1:-/var/local/emhttp/disks.ini}"
  [[ -f "$ini" ]] || return 1
  awk '
    /^\[/ {
      if (sec != "" && tolower(typ) == "cache" && size+0 > 0)
        printf "%s\t%s\n", sec, size
      s=$0
      gsub(/^\[|\]$/, "", s)
      sec=s; typ=""; size=0
      next
    }
    {
      line=$0
      gsub(/\r/, "", line)
      if (line ~ /^type=/) {
        typ=line; sub(/^type=/, "", typ); gsub(/^"|"$/, "", typ)
      }
      if (line ~ /^fsSize=/) {
        size=line; sub(/^fsSize=/, "", size); gsub(/^"|"$/, "", size)
      }
    }
    END {
      if (sec != "" && tolower(typ) == "cache" && size+0 > 0)
        printf "%s\t%s\n", sec, size
    }
  ' "$ini" | sort -t$'\t' -k2,2nr
}

# Wählt Pool-Namen: bevorzugter Name nur wenn er nicht deutlich kleiner ist als der größte Cache-Pool.
# Sonst: größter type=Cache (wie typische Unraid-Main-Anzeige der Primär-SSD).
ushm_unraid_pick_cache_pool() {
  local prefer="${1:-}"
  local ini="/var/local/emhttp/disks.ini"
  [[ -f "$ini" ]] || return 1

  local list
  list=$(ushm_unraid_list_cache_pools "$ini" 2>/dev/null) || true
  [[ -n "$list" ]] || return 1

  local largest_name="" largest_size=0 name size prefer_size="" prefer_name="" prefer_l
  prefer_l=$(printf '%s' "$prefer" | tr '[:upper:]' '[:lower:]')

  while IFS=$'\t' read -r name size; do
    [[ -z "$name" ]] && continue
    if [[ -z "$largest_name" ]]; then
      largest_name="$name"
      largest_size="${size:-0}"
    fi
    if [[ -n "$prefer" && "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == "$prefer_l" ]]; then
      prefer_size="${size:-0}"
      prefer_name="$name"
    fi
  done <<<"$list"

  [[ -n "$largest_name" ]] || return 1

  # Expliziter CACHE_PATH-Treffer (case-insensitive) → echten Section-Namen nutzen
  if [[ -n "$prefer_name" ]]; then
    if (( largest_size <= 0 || prefer_size * 2 >= largest_size )); then
      echo "$prefer_name"
      return 0
    fi
    ushm_warn "Cache-Pool '$prefer_name' ist klein gegenüber '$largest_name' – nutze '$largest_name' (WebGUI-Größe)"
    echo "$largest_name"
    return 0
  fi

  # Fallback: „cache“ wenn vorhanden und nicht winzig
  while IFS=$'\t' read -r name size; do
    if [[ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == "cache" ]]; then
      if (( largest_size <= 0 || size * 2 >= largest_size )); then
        echo "$name"
        return 0
      fi
      break
    fi
  done <<<"$list"

  echo "$largest_name"
  return 0
}

# ---------------------------------------------------------------------------
# Nutzbare FS-Größe (Kernel/statvfs) – bei Btrfs-RAID1 ~1× Disk, nicht Summe
# Setzt: DF_TOTAL DF_USED DF_AVAIL DF_PCT DF_SOURCE
# ---------------------------------------------------------------------------
ushm_statvfs() {
  local path="$1"
  DF_TOTAL=0; DF_USED=0; DF_AVAIL=0; DF_PCT=0; DF_SOURCE=""
  [[ -e "$path" ]] || return 1

  local out
  # Python immer auf Unraid; gleiche API wie df (f_blocks / f_bavail)
  if command -v python3 >/dev/null 2>&1; then
    out=$(python3 -c '
import os, sys
p = sys.argv[1]
st = os.statvfs(p)
b = st.f_frsize
total = b * st.f_blocks
free = b * st.f_bavail
used = total - (b * st.f_bfree)
if used < 0:
    used = 0
print("%d %d %d" % (total, used, free))
' "$path" 2>/dev/null) || true
  elif command -v python >/dev/null 2>&1; then
    out=$(python -c '
import os, sys
p = sys.argv[1]
st = os.statvfs(p)
b = st.f_frsize
total = b * st.f_blocks
free = b * st.f_bavail
used = total - (b * st.f_bfree)
if used < 0:
    used = 0
print("%d %d %d" % (total, used, free))
' "$path" 2>/dev/null) || true
  fi

  if [[ -n "$out" ]]; then
    local t u a
    read -r t u a <<<"$out"
    if [[ "$t" =~ ^[0-9]+$ && "$t" -gt 0 ]]; then
      DF_TOTAL=$t
      DF_USED=$u
      DF_AVAIL=$a
      DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
      (( DF_PCT < 0 )) && DF_PCT=0
      (( DF_PCT > 100 )) && DF_PCT=100
      DF_SOURCE="statvfs"
      return 0
    fi
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Btrfs: nur Fallback. RAID1 → Total = Device size / Data ratio (nie Roh-Summe).
# ---------------------------------------------------------------------------
ushm_btrfs_usage() {
  local path="$1"
  BTRFS_TOTAL=0; BTRFS_USED=0; BTRFS_FREE=0
  command -v btrfs >/dev/null 2>&1 || return 1
  [[ -e "$path" ]] || return 1

  local raw
  raw=$(btrfs filesystem usage -b "$path" 2>/dev/null) || return 1
  [[ -n "$raw" ]] || return 1

  local device_size data_ratio
  device_size=$(awk '
    /Device size:/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
    }' <<<"$raw")

  data_ratio=$(awk '
    /Data ratio:/ {
      for (i = 1; i <= NF; i++)
        if ($i ~ /^[0-9]+([.][0-9]+)?$/) { print $i; exit }
    }' <<<"$raw")

  # Ratio oft fehlend/1 – dann aus Profil erraten (RAID1/RAID10/…)
  if [[ -z "$data_ratio" || "$data_ratio" == "1" || "$data_ratio" == "1.00" ]]; then
    if grep -qE 'Data,RAID1|Data,RAID1C3|Data,RAID1C4' <<<"$raw"; then
      data_ratio="2"
    elif grep -qE 'Data,RAID10' <<<"$raw"; then
      data_ratio="2"
    elif grep -qE 'Data,RAID5' <<<"$raw"; then
      data_ratio="1.25"
    elif grep -qE 'Data,RAID6' <<<"$raw"; then
      data_ratio="1.5"
    else
      # Anzahl Geräte: 2+ gleich große → RAID1-artig teilen wenn "RAID1" irgendwo
      local ndev
      ndev=$(grep -cE '^\s*devid\s' <<<"$raw" 2>/dev/null || echo 0)
      if grep -qi 'RAID1' <<<"$raw" && (( ndev >= 2 )); then
        data_ratio="2"
      else
        data_ratio="1"
      fi
    fi
  fi

  if [[ ! "$device_size" =~ ^[0-9]+$ || "$device_size" -le 0 ]]; then
    return 1
  fi

  BTRFS_TOTAL=$(awk -v ds="$device_size" -v r="$data_ratio" 'BEGIN {
    if (r+0 < 1) r=1
    printf "%.0f", ds / r
  }')

  BTRFS_FREE=$(awk '
    /Free \(statfs, df\):/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
    }' <<<"$raw")
  if [[ -z "$BTRFS_FREE" || "$BTRFS_FREE" == "0" ]]; then
    BTRFS_FREE=$(awk '
      /Free \(estimated\):/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
      }' <<<"$raw")
  fi

  [[ "$BTRFS_FREE" =~ ^[0-9]+$ ]] || return 1

  # Nie Free+Raw-Used als Total (das bläst RAID1 auf ~2×)
  if (( BTRFS_FREE > BTRFS_TOTAL )); then
    # Free ist maßgeblich – Total leicht anheben, aber nicht verdoppeln
    BTRFS_TOTAL=$BTRFS_FREE
  fi
  BTRFS_USED=$(( BTRFS_TOTAL - BTRFS_FREE ))
  (( BTRFS_USED < 0 )) && BTRFS_USED=0

  [[ "$BTRFS_TOTAL" -gt 0 ]] || return 1
  return 0
}

# System-df ohne Btrfs/disks.ini (nukleare Cache-Variante)
ushm_df_system() {
  local path="$1"
  DF_TOTAL=0; DF_USED=0; DF_AVAIL=0; DF_PCT=0; DF_SOURCE=""
  [[ -e "$path" ]] || return 1

  local t=0 u=0 a=0 p=0
  local parsed=0

  if command -v df >/dev/null 2>&1; then
    local out pc
    # GNU
    if out=$(df -B1 --output=size,used,avail,pcent "$path" 2>/dev/null | awk 'NR==2 {print}'); then
      read -r t u a pc <<<"$out"
      if [[ "$t" =~ ^[0-9]+$ && "$t" -gt 0 ]]; then
        p=${pc%%%}; p=${p// /}
        parsed=1
      fi
    fi
    if (( parsed == 0 )); then
      local line
      line=$(df -Pk "$path" 2>/dev/null | awk 'NR>1 { line=$0 } END { print line }')
      if [[ -n "$line" ]]; then
        local -a f=()
        # shellcheck disable=SC2206
        f=($line)
        local i pct_i=-1
        for (( i=0; i<${#f[@]}; i++ )); do
          if [[ "${f[i]}" == *% ]]; then pct_i=$i; break; fi
        done
        if (( pct_i >= 3 )); then
          t="${f[pct_i-3]}"; u="${f[pct_i-2]}"; a="${f[pct_i-1]}"
          p="${f[pct_i]%%%}"
          t=$(( t * 1024 )); u=$(( u * 1024 )); a=$(( a * 1024 ))
          parsed=1
        fi
      fi
    fi
  fi

  (( parsed == 1 )) || return 1
  [[ "$t" =~ ^[0-9]+$ && "$t" -gt 0 ]] || return 1

  DF_TOTAL=$t
  DF_USED=$u
  if [[ "$a" =~ ^[0-9]+$ ]]; then
    DF_AVAIL=$a
  else
    DF_AVAIL=$(( t > u ? t - u : 0 ))
  fi
  DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
  (( DF_PCT < 0 )) && DF_PCT=0
  (( DF_PCT > 100 )) && DF_PCT=100
  DF_SOURCE="df"
  return 0
}

# df: total/used/avail bytes + use% für einen Mount
# Setzt: DF_TOTAL DF_USED DF_AVAIL DF_PCT DF_SOURCE
#
# Prefer: statvfs → df → (optional disks.ini) → btrfs ratio-adj
ushm_df() {
  local path="$1"
  local prefer_unraid="${2:-auto}" # auto|yes|no
  DF_TOTAL=0; DF_USED=0; DF_AVAIL=0; DF_PCT=0; DF_SOURCE=""
  [[ -e "$path" || "$prefer_unraid" == "yes" ]] || return 1

  # Mount: immer zuerst Kernel-Statistik (korrekt für RAID1)
  if [[ -e "$path" ]] && ushm_statvfs "$path"; then
    ushm_debug "df via statvfs: total=$DF_TOTAL used=$DF_USED free=$DF_AVAIL (${DF_PCT}%)"
    return 0
  fi
  if [[ -e "$path" ]] && ushm_df_system "$path"; then
    ushm_debug "df via system df: total=$DF_TOTAL used=$DF_USED free=$DF_AVAIL (${DF_PCT}%)"
    return 0
  fi

  if [[ "$prefer_unraid" != "no" && -f /var/local/emhttp/disks.ini ]]; then
    local pool_name
    pool_name=$(basename "$path")
    if [[ "$path" == /mnt/* && "$pool_name" != "user" && "$pool_name" != disk* ]]; then
      if ushm_unraid_disk_stats "$pool_name"; then
        DF_TOTAL=$UNRAID_FS_TOTAL
        DF_USED=$UNRAID_FS_USED
        DF_AVAIL=$UNRAID_FS_FREE
        DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
        (( DF_PCT < 0 )) && DF_PCT=0
        (( DF_PCT > 100 )) && DF_PCT=100
        DF_SOURCE="disks.ini"
        ushm_debug "df via disks.ini [$pool_name]: total=$DF_TOTAL used=$DF_USED free=$DF_AVAIL (${DF_PCT}%)"
        return 0
      fi
    fi
  fi

  [[ -e "$path" ]] || return 1
  local fstype=""
  fstype=$(findmnt -n -o FSTYPE "$path" 2>/dev/null || true)
  if [[ "${fstype,,}" == *btrfs* ]] && ushm_btrfs_usage "$path"; then
    DF_TOTAL=$BTRFS_TOTAL
    DF_USED=$BTRFS_USED
    DF_AVAIL=$BTRFS_FREE
    DF_PCT=$(( DF_USED * 100 / DF_TOTAL ))
    (( DF_PCT < 0 )) && DF_PCT=0
    (( DF_PCT > 100 )) && DF_PCT=100
    DF_SOURCE="btrfs"
    ushm_debug "df via btrfs: total=$DF_TOTAL used=$DF_USED free=$DF_AVAIL (${DF_PCT}%)"
    return 0
  fi

  return 1
}
