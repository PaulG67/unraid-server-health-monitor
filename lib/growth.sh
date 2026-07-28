#!/usr/bin/env bash
# Wachstum seit letztem Lauf
# shellcheck disable=SC2034

ushm_format_delta() {
  local delta="${1:-0}"
  if (( delta > 0 )); then
    printf '+%s' "$(ushm_bytes_human "$delta")"
  elif (( delta < 0 )); then
    printf '-%s' "$(ushm_bytes_human $(( -delta )) )"
  else
    printf '%s' "0 B"
  fi
}

ushm_check_growth() {
  GROWTH_TOP=""
  GROWTH_TOTAL_DELTA=0
  declare -g -a GROWTH_NAMES=()
  declare -g -a GROWTH_DELTAS=()

  local state_file="${DATA_DIR}/state/appdata_sizes.csv"
  local prev_file="${DATA_DIR}/state/appdata_sizes.prev.csv"
  ushm_info "Berechne AppData-Wachstum"

  {
    echo "name,bytes,timestamp"
    local i
    for i in "${!APPDATA_NAMES[@]}"; do
      printf '%s,%s,%s\n' "${APPDATA_NAMES[$i]}" "${APPDATA_SIZES[$i]}" "$(date -Iseconds)"
    done
  } >"$state_file"

  if [[ ! -f "$prev_file" ]]; then
    ushm_info "Kein vorheriger Snapshot – Wachstum wird ab dem nächsten Lauf berechnet"
    cp -f "$state_file" "$prev_file"
    GROWTH_TOP="(erster Lauf – noch keine Vergleichsdaten)"
    return 0
  fi

  declare -A prev=()
  local name bytes ts
  while IFS=',' read -r name bytes ts; do
    [[ "$name" == "name" ]] && continue
    [[ -z "$name" ]] && continue
    prev["$name"]="$bytes"
  done <"$prev_file"

  local tmp
  tmp=$(mktemp)
  local i delta
  for i in "${!APPDATA_NAMES[@]}"; do
    name="${APPDATA_NAMES[$i]}"
    bytes="${APPDATA_SIZES[$i]}"
    local old="${prev[$name]:-0}"
    delta=$(( bytes - old ))
    GROWTH_TOTAL_DELTA=$(( GROWTH_TOTAL_DELTA + delta ))
    printf '%s\t%s\n' "$delta" "$name" >>"$tmp"
  done

  while IFS=$'\t' read -r delta name; do
    GROWTH_NAMES+=("$name")
    GROWTH_DELTAS+=("$delta")
  done < <(sort -nr "$tmp" | head -n "${TOP_N:-20}")

  rm -f "$tmp"

  GROWTH_TOP=""
  for i in "${!GROWTH_NAMES[@]}"; do
    delta="${GROWTH_DELTAS[$i]}"
    name="${GROWTH_NAMES[$i]}"
    # Top 8 oder Änderung >= 1 MB
    if (( i < 8 || delta >= 1048576 || delta <= -1048576 )); then
      GROWTH_TOP+="$(printf '%-20s %s' "$name" "$(ushm_format_delta "$delta")")"
      GROWTH_TOP+=$'\n'
    fi
  done

  local warn_b crit_b
  warn_b=$(ushm_mb_to_bytes "$APP_WARN_MB")
  crit_b=$(ushm_mb_to_bytes "$APP_CRIT_MB")

  for i in "${!GROWTH_NAMES[@]}"; do
    delta="${GROWTH_DELTAS[$i]}"
    name="${GROWTH_NAMES[$i]}"
    (( delta <= 0 )) && continue
    if (( delta >= crit_b )); then
      ushm_add_alert 2 "AppData Wachstum" "${name}: $(ushm_format_delta "$delta") seit letztem Lauf (kritisch ≥${APP_CRIT_MB} MB)"
    elif (( delta >= warn_b )); then
      ushm_add_alert 1 "AppData Wachstum" "${name}: $(ushm_format_delta "$delta") seit letztem Lauf (Warnung ≥${APP_WARN_MB} MB)"
    fi
  done

  cp -f "$state_file" "$prev_file"
  return 0
}
