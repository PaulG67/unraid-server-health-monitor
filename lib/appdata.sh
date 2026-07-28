#!/usr/bin/env bash
# AppData Top-N Verzeichnisse
# shellcheck disable=SC2034

ushm_check_appdata() {
  APPDATA_OK=0
  APPDATA_TOTAL_BYTES=0
  APPDATA_TOP=""
  declare -g -a APPDATA_NAMES=()
  declare -g -a APPDATA_SIZES=()

  local path="${APPDATA_PATH:-/mnt/user/appdata}"
  local n="${TOP_N:-20}"
  ushm_info "Prüfe AppData: $path (Top $n)"
  ushm_info "  → scanne Verzeichnisse (kann bei großen Apps 1–5 Min dauern)…"

  if [[ ! -d "$path" ]]; then
    ushm_add_alert 2 "AppData" "AppData-Pfad nicht gefunden: $path"
    return 1
  fi

  APPDATA_OK=1

  # Ein einziger Tiefen-1-Scan statt je Ordner einzeln
  local tmp
  tmp=$(mktemp)
  local du_ok=0
  if du -d1 -b "$path" 2>/dev/null | sort -nr >"$tmp"; then
    du_ok=1
  elif du --max-depth=1 -b "$path" 2>/dev/null | sort -nr >"$tmp"; then
    du_ok=1
  fi

  if (( du_ok == 1 )) && [[ -s "$tmp" ]]; then
    local converted bytes p name
    converted=$(mktemp)
    while read -r bytes p; do
      [[ -z "$bytes" || -z "$p" ]] && continue
      [[ "$bytes" =~ ^[0-9]+$ ]] || continue
      if [[ "$p" == "$path" || "$p" == "${path%/}" ]]; then
        APPDATA_TOTAL_BYTES="$bytes"
        continue
      fi
      name=$(basename "$p")
      printf '%s\t%s\n' "$bytes" "$name" >>"$converted"
    done <"$tmp"
    mv -f "$converted" "$tmp"
  else
    ushm_warn "du -d1 nicht verfügbar – Fallback (langsamer)"
    : >"$tmp"
    local d
    shopt -s nullglob
    for d in "$path"/*/; do
      [[ -d "$d" ]] || continue
      local sz name
      name=$(basename "$d")
      ushm_info "  → messe $name …"
      sz=$(ushm_dir_size_bytes "$d")
      printf '%s\t%s\n' "$sz" "$name" >>"$tmp"
    done
    shopt -u nullglob
    sort -nr -o "$tmp" "$tmp"
  fi

  # Falls Total nicht aus Parent-Zeile kam: Summe der Kinder
  if [[ "${APPDATA_TOTAL_BYTES:-0}" -eq 0 ]]; then
    APPDATA_TOTAL_BYTES=$(awk -F'\t' '{s+=$1} END{print s+0}' "$tmp")
  fi

  local sz name i=0
  while IFS=$'\t' read -r sz name; do
    [[ -z "$name" ]] && continue
    (( i++ > n )) && break
    APPDATA_NAMES+=("$name")
    APPDATA_SIZES+=("$sz")
  done <"$tmp"

  rm -f "$tmp"

  APPDATA_TOP=""
  for i in "${!APPDATA_NAMES[@]}"; do
    APPDATA_TOP+="$(printf '%-20s %10s\n' "${APPDATA_NAMES[$i]}" "$(ushm_bytes_human "${APPDATA_SIZES[$i]}")")"
  done

  ushm_info "AppData fertig: $(ushm_bytes_human "$APPDATA_TOTAL_BYTES"), ${#APPDATA_NAMES[@]} Einträge"
  return 0
}
