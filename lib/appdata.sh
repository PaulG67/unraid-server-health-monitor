#!/usr/bin/env bash
# AppData Top-N Verzeichnisse
# shellcheck disable=SC2034

# APPDATA_OK APPDATA_TOTAL_BYTES APPDATA_TOP (Name\tBytes Zeilen)
# APPDATA_NAMES[] APPDATA_SIZES[] parallel arrays

ushm_check_appdata() {
  APPDATA_OK=0
  APPDATA_TOTAL_BYTES=0
  APPDATA_TOP=""
  declare -g -a APPDATA_NAMES=()
  declare -g -a APPDATA_SIZES=()

  local path="${APPDATA_PATH:-/mnt/user/appdata}"
  local n="${TOP_N:-20}"
  ushm_info "Prüfe AppData: $path (Top $n)"

  if [[ ! -d "$path" ]]; then
    ushm_add_alert 2 "AppData" "AppData-Pfad nicht gefunden: $path"
    return 1
  fi

  APPDATA_OK=1
  APPDATA_TOTAL_BYTES=$(ushm_dir_size_bytes "$path")

  # Kinder-Verzeichnisse nach Größe sortieren
  local tmp
  tmp=$(mktemp)
  local d
  shopt -s nullglob
  for d in "$path"/*/; do
    [[ -d "$d" ]] || continue
    local sz name
    sz=$(ushm_dir_size_bytes "$d")
    name=$(basename "$d")
    printf '%s\t%s\n' "$sz" "$name" >>"$tmp"
  done
  shopt -u nullglob

  # Auch Dateien direkt in appdata (selten)
  # sortiert Top N
  local line sz name i=0
  while IFS=$'\t' read -r sz name; do
    (( i++ > n )) && break
    APPDATA_NAMES+=("$name")
    APPDATA_SIZES+=("$sz")
  done < <(sort -nr "$tmp")

  rm -f "$tmp"

  # Textblock für Report
  APPDATA_TOP=""
  local i
  for i in "${!APPDATA_NAMES[@]}"; do
    APPDATA_TOP+="$(printf '%-20s %10s\n' "${APPDATA_NAMES[$i]}" "$(ushm_bytes_human "${APPDATA_SIZES[$i]}")")"
  done

  ushm_debug "AppData gesamt: $(ushm_bytes_human "$APPDATA_TOTAL_BYTES"), ${#APPDATA_NAMES[@]} Einträge"
  return 0
}
