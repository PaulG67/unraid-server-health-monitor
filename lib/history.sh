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

  ushm_info "Historie geschrieben nach $hist_dir"
}
