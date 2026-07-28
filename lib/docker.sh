#!/usr/bin/env bash
# Docker Image / Writable Layer / Logs Monitoring
# shellcheck disable=SC2034

# DOCKER_OK DOCKER_TOTAL DOCKER_USED DOCKER_AVAIL DOCKER_PCT
# DOCKER_LAYER_BYTES DOCKER_LOG_BYTES DOCKER_LOG_TOP (multiline)

ushm_check_docker() {
  DOCKER_OK=0
  DOCKER_TOTAL=0
  DOCKER_USED=0
  DOCKER_AVAIL=0
  DOCKER_PCT=0
  DOCKER_BAR=""
  DOCKER_LAYER_BYTES=0
  DOCKER_LOG_BYTES=0
  DOCKER_LOG_TOP=""
  DOCKER_MODE="unknown"

  local path="${DOCKER_PATH:-/var/lib/docker}"
  ushm_info "Prüfe Docker: $path"

  if [[ ! -e "$path" ]]; then
    ushm_add_alert 1 "Docker" "Docker-Pfad nicht gefunden: $path (Docker ggf. gestoppt)"
    DOCKER_BAR="──────────── n/a"
    return 1
  fi

  # Erkennung: loopback docker.img vs. directory/folder mode
  if mount | grep -q " on ${path} "; then
    DOCKER_MODE="image"
  elif [[ -d "$path" ]]; then
    DOCKER_MODE="directory"
  fi

  if ushm_df "$path"; then
    DOCKER_OK=1
    DOCKER_TOTAL=$DF_TOTAL
    DOCKER_USED=$DF_USED
    DOCKER_AVAIL=$DF_AVAIL
    DOCKER_PCT=$DF_PCT
    DOCKER_BAR="$(ushm_pct_bar "$DOCKER_PCT")"
  else
    ushm_add_alert 1 "Docker" "df fehlgeschlagen für $path"
    return 1
  fi

  ushm_debug "Docker (${DOCKER_MODE}): ${DOCKER_PCT}% belegt ($(ushm_bytes_human "$DOCKER_USED") / $(ushm_bytes_human "$DOCKER_TOTAL"))"

  if (( DOCKER_PCT >= DOCKER_CRIT )); then
    ushm_add_alert 2 "Docker" "Docker-Image ${DOCKER_PCT}% belegt – kritisch ≥${DOCKER_CRIT}%"
  elif (( DOCKER_PCT >= DOCKER_WARN )); then
    ushm_add_alert 1 "Docker" "Docker-Image ${DOCKER_PCT}% belegt – Warnung ≥${DOCKER_WARN}%"
  fi

  # Writable Layer nur scannen wenn Schwellwert aktiv (sonst sehr langsam!)
  ushm_docker_writable_layer
  ushm_info "  → prüfe Container-Logs…"
  ushm_docker_logs
  ushm_info "Docker-Check fertig (${DOCKER_PCT}% belegt)"

  return 0
}

ushm_docker_writable_layer() {
  DOCKER_LAYER_BYTES=0

  # Teurer du auf overlay2 – nur wenn gewünscht
  if (( ${DOCKER_LAYER_WARN:-0} <= 0 && ${DOCKER_LAYER_CRIT:-0} <= 0 )); then
    ushm_debug "Writable-Layer-Scan übersprungen (DOCKER_LAYER_WARN/CRIT=0)"
    return 0
  fi

  local path="${DOCKER_PATH:-/var/lib/docker}"
  local candidates=(
    "${path}/overlay2"
    "${path}/btrfs"
    "${path}/vfs"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      ushm_info "  → messe Writable Layer ($c) – kann dauern…"
      DOCKER_LAYER_BYTES=$(ushm_dir_size_bytes "$c")
      ushm_debug "Writable Layer ($c): $(ushm_bytes_human "$DOCKER_LAYER_BYTES")"
      break
    fi
  done

  if (( DOCKER_TOTAL > 0 )); then
    local layer_pct=$(( DOCKER_LAYER_BYTES * 100 / DOCKER_TOTAL ))
    if (( DOCKER_LAYER_CRIT > 0 && layer_pct >= DOCKER_LAYER_CRIT )); then
      ushm_add_alert 2 "Docker Layer" "Writable Layer ${layer_pct}% des Docker-Speichers – kritisch ≥${DOCKER_LAYER_CRIT}%"
    elif (( DOCKER_LAYER_WARN > 0 && layer_pct >= DOCKER_LAYER_WARN )); then
      ushm_add_alert 1 "Docker Layer" "Writable Layer ${layer_pct}% des Docker-Speichers – Warnung ≥${DOCKER_LAYER_WARN}%"
    fi
  fi
}

ushm_docker_logs() {
  local path="${DOCKER_PATH:-/var/lib/docker}"
  local log_root="${path}/containers"
  DOCKER_LOG_BYTES=0
  DOCKER_LOG_TOP=""

  if [[ ! -d "$log_root" ]]; then
    ushm_debug "Keine Docker-Container-Logs unter $log_root"
    return 0
  fi

  # Gesamtgröße aller *-json.log (nur Dateigrößen, kein rekursives du)
  local sum
  sum=$(find "$log_root" -type f -name '*-json.log' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  DOCKER_LOG_BYTES=${sum:-0}

  # Top 10 größte Logfiles
  DOCKER_LOG_TOP=$(find "$log_root" -type f -name '*-json.log' -printf '%s\t%p\n' 2>/dev/null \
    | sort -nr \
    | head -n 10 \
    | while IFS=$'\t' read -r sz p; do
        local name
        name=$(basename "$(dirname "$p")")
        # Kurzname aus container config.json falls möglich
        local cname=""
        if [[ -f "$(dirname "$p")/config.v2.json" ]]; then
          cname=$(grep -oE '"Name":"[^"]+"' "$(dirname "$p")/config.v2.json" 2>/dev/null | head -1 | cut -d'"' -f4)
          cname=${cname#/}
        fi
        [[ -z "$cname" ]] && cname="${name:0:12}"
        printf '%s\t%s\n' "$(ushm_bytes_human "$sz")" "$cname"
      done)

  ushm_debug "Docker Logs gesamt: $(ushm_bytes_human "$DOCKER_LOG_BYTES")"

  local log_mb
  log_mb=$(ushm_bytes_to_mb "$DOCKER_LOG_BYTES")
  if (( log_mb >= LOG_CRIT_MB )); then
    ushm_add_alert 2 "Container Logs" "Container-Logs ${log_mb} MB – kritisch ≥${LOG_CRIT_MB} MB"
  elif (( log_mb >= LOG_WARN_MB )); then
    ushm_add_alert 1 "Container Logs" "Container-Logs ${log_mb} MB – Warnung ≥${LOG_WARN_MB} MB"
  fi
}
