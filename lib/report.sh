#!/usr/bin/env bash
# Text- und HTML-Reports (Dashboard im Log)
# shellcheck disable=SC2034

ushm_hr() {
  echo "-----------------------------------------"
}

ushm_report_text() {
  local host
  host="$(ushm_hostname)"

  cat <<EOF
=========================================
 Unraid Server Health Monitor
=========================================

Server

${USHM_OK} Online  (${host})
$(date '+%Y-%m-%d %H:%M:%S')

$(ushm_hr)

Cache SSD

${CACHE_BAR:-n/a}
$(ushm_bytes_human "${CACHE_AVAIL:-0}") frei  (${CACHE_PCT_FREE:-?}% free)

$(ushm_hr)

Docker Image

${DOCKER_BAR:-n/a}
Mode: ${DOCKER_MODE:-?}
$(ushm_bytes_human "${DOCKER_USED:-0}") / $(ushm_bytes_human "${DOCKER_TOTAL:-0}")
Writable Layer: $(ushm_bytes_human "${DOCKER_LAYER_BYTES:-0}")
Container Logs: $(ushm_bytes_human "${DOCKER_LOG_BYTES:-0}")

$(ushm_hr)

Top AppData

${APPDATA_TOP:-(keine Daten)}
Gesamt: $(ushm_bytes_human "${APPDATA_TOTAL_BYTES:-0}")

$(ushm_hr)

Größtes Wachstum

${GROWTH_TOP:-(keine Daten)}

$(ushm_hr)

Status

$(ushm_severity_emoji) $(ushm_severity_label)
EOF

  if (( ${#USHM_ALERTS[@]} > 0 )); then
    echo
    echo "Alarme"
    echo
    local entry level cat msg
    for entry in "${USHM_ALERTS[@]}"; do
      IFS='|' read -r level cat msg <<<"$entry"
      if (( level >= 2 )); then
        echo "${USHM_RED} [CRIT] [$cat] $msg"
      else
        echo "${USHM_YELLOW} [WARN] [$cat] $msg"
      fi
    done
  fi

  echo
  echo "========================================="
}

ushm_report_pushover() {
  local lines=()
  lines+=("Cache: ${CACHE_PCT_USED:-?}% used, $(ushm_bytes_human "${CACHE_AVAIL:-0}") free")
  lines+=("Docker: ${DOCKER_PCT:-?}%")
  lines+=("AppData: $(ushm_bytes_human "${APPDATA_TOTAL_BYTES:-0}")")
  lines+=("Logs: $(ushm_bytes_human "${DOCKER_LOG_BYTES:-0}")")
  lines+=("Status: $(ushm_severity_label)")

  if (( ${#USHM_ALERTS[@]} > 0 )); then
    lines+=("")
    local entry level cat msg count=0
    for entry in "${USHM_ALERTS[@]}"; do
      (( count++ > 5 )) && { lines+=("…"); break; }
      IFS='|' read -r level cat msg <<<"$entry"
      lines+=("• [$cat] $msg")
    done
  fi

  printf '%s\n' "${lines[@]}"
}

ushm_report_html() {
  local host emoji status
  host="$(ushm_hostname)"
  emoji="$(ushm_severity_emoji)"
  status="$(ushm_severity_label)"

  local status_color="#16a34a"
  (( USHM_SEVERITY == 1 )) && status_color="#ca8a04"
  (( USHM_SEVERITY >= 2 )) && status_color="#dc2626"

  local alerts_html=""
  if (( ${#USHM_ALERTS[@]} > 0 )); then
    alerts_html="<h3>Alarme</h3><ul>"
    local entry level cat msg
    for entry in "${USHM_ALERTS[@]}"; do
      IFS='|' read -r level cat msg <<<"$entry"
      local c="#ca8a04"
      (( level >= 2 )) && c="#dc2626"
      alerts_html+="<li style=\"color:${c}\"><strong>[${cat}]</strong> ${msg}</li>"
    done
    alerts_html+="</ul>"
  fi

  # AppData rows
  local app_rows=""
  local i
  for i in "${!APPDATA_NAMES[@]}"; do
    (( i >= 10 )) && break
    app_rows+="<tr><td>${APPDATA_NAMES[$i]}</td><td style=\"text-align:right\">$(ushm_bytes_human "${APPDATA_SIZES[$i]}")</td></tr>"
  done

  local growth_rows=""
  for i in "${!GROWTH_NAMES[@]}"; do
    (( i >= 8 )) && break
    local d="${GROWTH_DELTAS[$i]}"
    local sign="+"
    local abs="$d"
    if (( d < 0 )); then
      sign="-"
      abs=$(( -d ))
    elif (( d == 0 )); then
      sign=""
    fi
    growth_rows+="<tr><td>${GROWTH_NAMES[$i]}</td><td style=\"text-align:right\">${sign}$(ushm_bytes_human "$abs")</td></tr>"
  done

  cat <<EOF
<!DOCTYPE html>
<html lang="de">
<head><meta charset="UTF-8"><title>USHM Report</title></head>
<body style="font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;background:#0f172a;color:#e2e8f0;margin:0;padding:24px;">
  <div style="max-width:640px;margin:0 auto;background:#1e293b;border-radius:12px;padding:28px;">
    <h1 style="margin:0 0 4px;font-size:22px;">Unraid Server Health Monitor</h1>
    <p style="margin:0 0 20px;color:#94a3b8;">${host} · $(date '+%Y-%m-%d %H:%M:%S')</p>

    <div style="background:#0f172a;border-radius:8px;padding:16px;margin-bottom:16px;">
      <div style="font-size:13px;color:#94a3b8;text-transform:uppercase;letter-spacing:.05em;">Status</div>
      <div style="font-size:28px;color:${status_color};margin-top:4px;">${emoji} ${status}</div>
    </div>

    <table style="width:100%;border-collapse:collapse;margin-bottom:16px;">
      <tr>
        <td style="padding:12px;background:#0f172a;border-radius:8px;width:50%;vertical-align:top;">
          <div style="font-size:12px;color:#94a3b8;">CACHE SSD</div>
          <div style="font-size:20px;margin:6px 0;">${CACHE_PCT_USED:-?}%</div>
          <div style="font-family:monospace;font-size:12px;color:#64748b;">${CACHE_BAR:-}</div>
          <div style="margin-top:6px;color:#94a3b8;">$(ushm_bytes_human "${CACHE_AVAIL:-0}") frei</div>
        </td>
        <td style="width:12px;"></td>
        <td style="padding:12px;background:#0f172a;border-radius:8px;width:50%;vertical-align:top;">
          <div style="font-size:12px;color:#94a3b8;">DOCKER</div>
          <div style="font-size:20px;margin:6px 0;">${DOCKER_PCT:-?}%</div>
          <div style="font-family:monospace;font-size:12px;color:#64748b;">${DOCKER_BAR:-}</div>
          <div style="margin-top:6px;color:#94a3b8;">Logs $(ushm_bytes_human "${DOCKER_LOG_BYTES:-0}")</div>
        </td>
      </tr>
    </table>

    <h3 style="margin:20px 0 8px;font-size:14px;color:#94a3b8;text-transform:uppercase;">Top AppData</h3>
    <table style="width:100%;border-collapse:collapse;font-size:14px;">${app_rows}</table>

    <h3 style="margin:20px 0 8px;font-size:14px;color:#94a3b8;text-transform:uppercase;">Wachstum</h3>
    <table style="width:100%;border-collapse:collapse;font-size:14px;">${growth_rows:-<tr><td>keine Daten</td></tr>}</table>

    ${alerts_html}

    <p style="margin-top:28px;font-size:11px;color:#64748b;">USHM v$(cat "${USHM_HOME}/VERSION" 2>/dev/null || echo "1.0") · CSV-Historie unter data/history/</p>
  </div>
</body>
</html>
EOF
}

ushm_print_dashboard() {
  ushm_report_text
}
