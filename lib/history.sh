#!/usr/bin/env bash
# CSV-Historie schreiben
# shellcheck disable=SC2034

ushm_history_write() {
  local hist_dir="${DATA_DIR}/history"
  ushm_mkdir_p "$hist_dir"

  local ts date_day
  ts="$(date -Iseconds)"
  date_day="$(date '+%Y-%m-%d')"

  # Tages-Snapshot Zusammenfassung
  local summary="${hist_dir}/summary.csv"
  if [[ ! -f "$summary" ]]; then
    echo "timestamp,hostname,severity,cache_pct_used,cache_pct_free,cache_avail_bytes,docker_pct,docker_used_bytes,appdata_bytes,growth_delta_bytes,docker_log_bytes,docker_layer_bytes" >"$summary"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$ts" \
    "$(ushm_hostname)" \
    "$(ushm_severity_label)" \
    "${CACHE_PCT_USED:-}" \
    "${CACHE_PCT_FREE:-}" \
    "${CACHE_AVAIL:-}" \
    "${DOCKER_PCT:-}" \
    "${DOCKER_USED:-}" \
    "${APPDATA_TOTAL_BYTES:-}" \
    "${GROWTH_TOTAL_DELTA:-}" \
    "${DOCKER_LOG_BYTES:-}" \
    "${DOCKER_LAYER_BYTES:-}" \
    >>"$summary"

  # AppData Detail pro Lauf
  local app_hist="${hist_dir}/appdata_${date_day}.csv"
  if [[ ! -f "$app_hist" ]]; then
    echo "timestamp,name,bytes" >"$app_hist"
  fi
  local i
  for i in "${!APPDATA_NAMES[@]}"; do
    printf '%s,%s,%s\n' "$ts" "${APPDATA_NAMES[$i]}" "${APPDATA_SIZES[$i]}" >>"$app_hist"
  done

  # Alerts Log
  if (( ${#USHM_ALERTS[@]} > 0 )); then
    local alert_hist="${hist_dir}/alerts.csv"
    if [[ ! -f "$alert_hist" ]]; then
      echo "timestamp,severity,category,message" >"$alert_hist"
    fi
    local entry level cat msg
    for entry in "${USHM_ALERTS[@]}"; do
      IFS='|' read -r level cat msg <<<"$entry"
      printf '%s,%s,%s,"%s"\n' "$ts" "$(ushm_severity_label "$level")" "$cat" "${msg//\"/\'}" >>"$alert_hist"
    done
  fi

  # Parity I/O-Fehler Historie
  if (( ${#PARITY_NAMES[@]} > 0 )); then
    local parity_hist="${hist_dir}/parity.csv"
    if [[ ! -f "$parity_hist" ]]; then
      echo "timestamp,name,device,status,num_errors,delta_errors,temp" >"$parity_hist"
    fi
    local i
    for i in "${!PARITY_NAMES[@]}"; do
      printf '%s,%s,%s,%s,%s,%s,%s\n' \
        "$ts" \
        "${PARITY_NAMES[$i]}" \
        "${PARITY_DEVICES[$i]:-}" \
        "${PARITY_STATUS[$i]:-}" \
        "${PARITY_ERRORS[$i]:-0}" \
        "${PARITY_DELTA_ERRORS[$i]:-0}" \
        "${PARITY_TEMP[$i]:-}" \
        >>"$parity_hist"
    done
  fi

  # Inventar-Änderungen
  DISK_INVENTORY_ADDED=("${DISK_INVENTORY_ADDED[@]+"${DISK_INVENTORY_ADDED[@]}"}")
  DISK_INVENTORY_REMOVED=("${DISK_INVENTORY_REMOVED[@]+"${DISK_INVENTORY_REMOVED[@]}"}")
  DISK_INVENTORY_REPLACED=("${DISK_INVENTORY_REPLACED[@]+"${DISK_INVENTORY_REPLACED[@]}"}")
  if (( ${#DISK_INVENTORY_ADDED[@]} > 0 || ${#DISK_INVENTORY_REMOVED[@]} > 0 || ${#DISK_INVENTORY_REPLACED[@]} > 0 )); then
    local inv_hist="${hist_dir}/inventory.csv"
    if [[ ! -f "$inv_hist" ]]; then
      echo "timestamp,change,detail" >"$inv_hist"
    fi
    local d
    for d in "${DISK_INVENTORY_ADDED[@]}"; do
      printf '%s,added,"%s"\n' "$ts" "${d//\"/\'}" >>"$inv_hist"
    done
    for d in "${DISK_INVENTORY_REMOVED[@]}"; do
      printf '%s,removed,"%s"\n' "$ts" "${d//\"/\'}" >>"$inv_hist"
    done
    for d in "${DISK_INVENTORY_REPLACED[@]}"; do
      printf '%s,replaced,"%s"\n' "$ts" "${d//\"/\'}" >>"$inv_hist"
    done
  fi

  # SMART Snapshot (eine Zeile pro SMART_LINES-Eintrag grob; Detail in state/)
  if [[ -n "${SMART_REPORT:-}" && "$SMART_REPORT" != "(keine Daten)" && "$SMART_REPORT" != "(smartctl fehlt)" ]]; then
    local smart_hist="${hist_dir}/smart_${date_day}.csv"
    if [[ ! -f "$smart_hist" ]]; then
      echo "timestamp,line" >"$smart_hist"
    fi
    local sline
    while IFS= read -r sline; do
      [[ -z "$sline" ]] && continue
      printf '%s,"%s"\n' "$ts" "${sline//\"/\'}" >>"$smart_hist"
    done <<<"$SMART_REPORT"
  fi

  ushm_info "Historie geschrieben nach $hist_dir"
}
