#!/usr/bin/env bash
# SMART Monitoring – alle Disks (Parity / Data / Cache), gruppiert
# shellcheck disable=SC2034

# Ergebnisse:
# SMART_LINES[] / SMART_REPORT / SMART_OK_COUNT / SMART_STANDBY_COUNT / SMART_FAIL_COUNT

ushm_smart_defaults() {
  USHM_SMART_ENABLED="${USHM_SMART_ENABLED:-true}"
  # all    = alle disks.ini-Disks mit device (außer flash) – Default
  # parity = nur Parity-Disks (weniger Spin-ups)
  SMART_SCOPE="${SMART_SCOPE:-all}"
  SMART_WARN="${SMART_WARN:-55}"
  SMART_CRIT="${SMART_CRIT:-65}"
  SMART_REALLOC_WARN="${SMART_REALLOC_WARN:-1}"
  SMART_PENDING_WARN="${SMART_PENDING_WARN:-1}"
  SMART_UNCORR_WARN="${SMART_UNCORR_WARN:-1}"
  SMART_CRC_WARN="${SMART_CRC_WARN:-10}"
  SMART_DELTA_ALERT="${SMART_DELTA_ALERT:-true}"
}

# Disks für SMART: name\tdevice\ttype
ushm_smart_target_list() {
  local scope="${SMART_SCOPE:-all}"
  local ini="/var/local/emhttp/disks.ini"
  [[ -f "$ini" ]] || return 1

  if [[ "${scope,,}" == "parity" ]]; then
    if (( ${#PARITY_NAMES[@]} > 0 )); then
      local i
      for i in "${!PARITY_NAMES[@]}"; do
        [[ -n "${PARITY_DEVICES[$i]:-}" ]] && printf '%s\t%s\tParity\n' "${PARITY_NAMES[$i]}" "${PARITY_DEVICES[$i]}"
      done
      return 0
    fi
    if declare -F ushm_array_list_parity >/dev/null; then
      ushm_array_list_parity 2>/dev/null | awk -F'\t' '{print $1"\t"$2"\tParity"}'
    fi
    return 0
  fi

  # alle Disks mit device, ohne Flash – Typ aus disks.ini
  if declare -F ushm_array_list_disks >/dev/null; then
    ushm_array_list_disks 2>/dev/null | awk -F'\t' '$3 != "" { print $1"\t"$3"\t"$2 }'
    return 0
  fi

  awk '
    /^\[/ {
      if (sec != "" && device != "" && tolower(typ) != "flash") {
        printf "%s\t%s\t%s\n", (name!=""?name:sec), device, typ
      }
      s=$0; gsub(/^\[|\]$/, "", s)
      sec=s; typ=""; name=""; device=""
      next
    }
    {
      line=$0; gsub(/\r/, "", line)
      if (line ~ /^type=/)   { typ=line; sub(/^type=/,"",typ); gsub(/^"|"$/,"",typ) }
      if (line ~ /^name=/)   { name=line; sub(/^name=/,"",name); gsub(/^"|"$/,"",name) }
      if (line ~ /^device=/) { device=line; sub(/^device=/,"",device); gsub(/^"|"$/,"",device) }
    }
    END {
      if (sec != "" && device != "" && tolower(typ) != "flash")
        printf "%s\t%s\t%s\n", (name!=""?name:sec), device, typ
    }
  ' "$ini"
}

ushm_smart_attr_raw() {
  local text="$1" id="$2" name_pat="$3"
  awk -v id="$id" -v np="$name_pat" '
    $1+0 == id+0 { print $NF; exit }
    np != "" && $0 ~ np { print $NF; exit }
  ' <<<"$text"
}

ushm_smart_temp_from_text() {
  local text="$1"
  local t
  t=$(ushm_smart_attr_raw "$text" 194 "Temperature_Celsius")
  if [[ "$t" =~ ^[0-9]+ ]]; then
    echo "${t%%[^0-9]*}"
    return 0
  fi
  t=$(ushm_smart_attr_raw "$text" 190 "Airflow_Temperature")
  if [[ "$t" =~ ^[0-9]+ ]]; then
    echo "${t%%[^0-9]*}"
    return 0
  fi
  t=$(awk -F: '/Temperature:/ { gsub(/[^0-9]/,"",$2); if($2!=""){print $2; exit}}' <<<"$text")
  [[ -n "$t" ]] && echo "$t" && return 0
  echo ""
}

ushm_smart_section_label() {
  case "${1,,}" in
    parity) echo "Parity" ;;
    data)   echo "Data" ;;
    cache)  echo "Cache" ;;
    *)      echo "${1:-Other}" ;;
  esac
}

ushm_smart_probe_disk() {
  # $1=name $2=device $3=type
  local name="$1" device="$2" typ="${3:-}"
  local devpath="/dev/${device}"
  [[ -b "$devpath" ]] || {
    ushm_warn "SMART ${name}: Gerät $devpath fehlt"
    SMART_LINES+=("SKIP|${typ}|${name}|Gerät /dev/${device} fehlt")
    return 1
  }

  local out rc=0 health="?" standby=0
  rc=0
  out=$(smartctl -n standby -H -A "$devpath" 2>&1) || rc=$?

  if (( (rc & 2) != 0 )) || grep -qiE 'device is in (STANDBY|SLEEP)|Device is in STANDBY' <<<"$out"; then
    standby=1
  fi

  if (( standby == 1 )); then
    SMART_STANDBY_COUNT=$(( SMART_STANDBY_COUNT + 1 ))
    SMART_LINES+=("STANDBY|${typ}|${name}|Standby – kein Spin-up")
    ushm_debug "SMART ${name}: standby"
    return 0
  fi

  if ! grep -qiE 'SMART (overall-health|Health) Status|PASSED|FAILED|OK' <<<"$out"; then
    rc=0
    out=$(smartctl -H -A "$devpath" 2>&1) || rc=$?
  fi

  if grep -qiE 'PASSED|OK' <<<"$out" && ! grep -qiE 'FAILED' <<<"$out"; then
    health="PASSED"
  elif grep -qiE 'FAILED' <<<"$out"; then
    health="FAILED"
  else
    health="UNKNOWN"
  fi

  local realloc pending uncorr reported crc temp
  realloc=$(ushm_smart_attr_raw "$out" 5 "Reallocated_Sector")
  pending=$(ushm_smart_attr_raw "$out" 197 "Current_Pending")
  uncorr=$(ushm_smart_attr_raw "$out" 198 "Offline_Uncorrectable")
  reported=$(ushm_smart_attr_raw "$out" 187 "Reported_Uncorrect")
  crc=$(ushm_smart_attr_raw "$out" 199 "UDMA_CRC_Error")
  temp=$(ushm_smart_temp_from_text "$out")

  realloc=${realloc%%[^0-9]*}; realloc=${realloc:-0}
  pending=${pending%%[^0-9]*}; pending=${pending:-0}
  uncorr=${uncorr%%[^0-9]*}; uncorr=${uncorr:-0}
  reported=${reported%%[^0-9]*}; reported=${reported:-0}
  crc=${crc%%[^0-9]*}; crc=${crc:-0}
  [[ "$realloc" =~ ^[0-9]+$ ]] || realloc=0
  [[ "$pending" =~ ^[0-9]+$ ]] || pending=0
  [[ "$uncorr" =~ ^[0-9]+$ ]] || uncorr=0
  [[ "$reported" =~ ^[0-9]+$ ]] || reported=0
  [[ "$crc" =~ ^[0-9]+$ ]] || crc=0

  local state_file have_prev=0
  state_file=$(ushm_state_file "smart_${name}")
  local prev_r=0 prev_p=0 prev_u=0 prev_ru=0 prev_c=0
  if [[ -f "$state_file" ]]; then
    have_prev=1
    prev_r=$(ushm_state_get "$state_file" "reallocated"); prev_r=${prev_r:-0}
    prev_p=$(ushm_state_get "$state_file" "pending"); prev_p=${prev_p:-0}
    prev_u=$(ushm_state_get "$state_file" "uncorrectable"); prev_u=${prev_u:-0}
    prev_ru=$(ushm_state_get "$state_file" "reported_uncorrect"); prev_ru=${prev_ru:-0}
    prev_c=$(ushm_state_get "$state_file" "crc"); prev_c=${prev_c:-0}
  fi
  [[ "$prev_r" =~ ^[0-9]+$ ]] || prev_r=0
  [[ "$prev_p" =~ ^[0-9]+$ ]] || prev_p=0
  [[ "$prev_u" =~ ^[0-9]+$ ]] || prev_u=0
  [[ "$prev_ru" =~ ^[0-9]+$ ]] || prev_ru=0
  [[ "$prev_c" =~ ^[0-9]+$ ]] || prev_c=0

  local d_r=0 d_p=0 d_u=0 d_ru=0 d_c=0
  if (( have_prev == 1 )); then
    d_r=$(( realloc - prev_r )); (( d_r < 0 )) && d_r=0
    d_p=$(( pending - prev_p )); (( d_p < 0 )) && d_p=0
    d_u=$(( uncorr - prev_u )); (( d_u < 0 )) && d_u=0
    d_ru=$(( reported - prev_ru )); (( d_ru < 0 )) && d_ru=0
    d_c=$(( crc - prev_c )); (( d_c < 0 )) && d_c=0
  fi

  ushm_state_set_many "$state_file" \
    "reallocated=${realloc}" \
    "pending=${pending}" \
    "uncorrectable=${uncorr}" \
    "reported_uncorrect=${reported}" \
    "crc=${crc}" \
    "temp=${temp}" \
    "health=${health}" \
    "device=${device}" \
    "type=${typ}" \
    "timestamp=$(date -Iseconds)"

  local deltas=()
  (( d_r > 0 )) && deltas+=("Realloc+${d_r}")
  (( d_p > 0 )) && deltas+=("Pending+${d_p}")
  (( d_u > 0 )) && deltas+=("OfflineUnc+${d_u}")
  (( d_ru > 0 )) && deltas+=("ReportedUnc+${d_ru}")
  (( d_c > 0 )) && deltas+=("CRC+${d_c}")
  local delta_txt=""
  if (( have_prev == 0 )); then
    delta_txt="  (Baseline)"
  elif (( ${#deltas[@]} > 0 )); then
    delta_txt="  Δ: $(IFS=,; echo "${deltas[*]}")"
  fi

  local temp_txt="${temp:-?}"
  local detail="${health}  T=${temp_txt}°C  Realloc=${realloc}  Pending=${pending}  OfflineUnc=${uncorr}  CRC=${crc}${delta_txt}"
  SMART_LINES+=("OK|${typ}|${name}|${detail}")

  if [[ "$health" == "FAILED" ]]; then
    SMART_FAIL_COUNT=$(( SMART_FAIL_COUNT + 1 ))
    ushm_add_alert 2 "SMART" "${name}: SMART Health FAILED"
  elif [[ "$health" == "PASSED" ]]; then
    SMART_OK_COUNT=$(( SMART_OK_COUNT + 1 ))
  fi

  if [[ "$temp" =~ ^[0-9]+$ ]]; then
    if (( temp >= SMART_CRIT )); then
      ushm_add_alert 2 "SMART" "${name}: Temperatur ${temp}°C ≥ ${SMART_CRIT}°C"
    elif (( temp >= SMART_WARN )); then
      ushm_add_alert 1 "SMART" "${name}: Temperatur ${temp}°C ≥ ${SMART_WARN}°C"
    fi
  fi

  if (( realloc >= SMART_REALLOC_WARN )); then
    ushm_add_alert 1 "SMART" "${name}: Reallocated_Sector_Ct=${realloc} (Disk zeigt umgelagerte Sektoren)"
  fi
  if (( pending >= SMART_PENDING_WARN )); then
    ushm_add_alert 2 "SMART" "${name}: Current_Pending_Sector=${pending} – kritische Sektoren wartend"
  fi
  if (( uncorr >= SMART_UNCORR_WARN )); then
    ushm_add_alert 2 "SMART" "${name}: Offline_Uncorrectable=${uncorr}"
  fi
  if (( reported >= SMART_REALLOC_WARN )); then
    ushm_add_alert 1 "SMART" "${name}: Reported_Uncorrect=${reported}"
  fi
  if (( crc >= SMART_CRC_WARN )); then
    ushm_add_alert 1 "SMART" "${name}: UDMA_CRC_Error_Count=${crc} (Kabel/Controller?)"
  fi

  if ushm_is_true "${SMART_DELTA_ALERT:-true}"; then
    if (( d_r > 0 )); then
      ushm_add_alert 2 "SMART" "${name}: Reallocated +${d_r} (jetzt ${realloc}) – Disk verschlechtert sich"
    fi
    if (( d_p > 0 )); then
      ushm_add_alert 2 "SMART" "${name}: Pending +${d_p} (jetzt ${pending})"
    fi
    if (( d_u > 0 )); then
      ushm_add_alert 2 "SMART" "${name}: Offline_Uncorrectable +${d_u} (jetzt ${uncorr})"
    fi
    if (( d_ru > 0 )); then
      ushm_add_alert 2 "SMART" "${name}: Reported_Uncorrect +${d_ru} (jetzt ${reported})"
    fi
    if (( d_c > 0 && d_c >= 5 )); then
      ushm_add_alert 1 "SMART" "${name}: CRC-Fehler +${d_c} (jetzt ${crc})"
    fi
  fi

  ushm_info "SMART ${name}: ${health} realloc=${realloc}(+${d_r}) pending=${pending}(+${d_p}) T=${temp:-?}"
  return 0
}

ushm_smart_format_report() {
  # SMART_LINES: status|type|name|detail → gruppiert nach Typ
  local summary="SMART Scope=${SMART_SCOPE} · OK=${SMART_OK_COUNT:-0}  Standby=${SMART_STANDBY_COUNT:-0}  Failed=${SMART_FAIL_COUNT:-0}"
  local out_lines=("$summary")

  if (( ${#SMART_LINES[@]} == 0 )); then
    out_lines+=("(keine SMART-Daten)")
    printf '%s\n' "${out_lines[@]}"
    return 0
  fi

  # Sort: Parity, Data, Cache, then name
  local sorted
  sorted=$(printf '%s\n' "${SMART_LINES[@]}" | awk -F'|' '{
    t=tolower($2)
    r=(t=="parity"?1:(t=="data"?2:(t=="cache"?3:9)))
    print r "|" $0
  }' | sort -t'|' -k1,1n -k4,4 | cut -d'|' -f2-)

  local cur=""
  local status typ name detail
  while IFS='|' read -r status typ name detail; do
    [[ -z "$name" ]] && continue
    local label
    label=$(ushm_smart_section_label "$typ")
    if [[ "$label" != "$cur" ]]; then
      cur="$label"
      out_lines+=("")
      out_lines+=("--- ${label} ---")
    fi
    if [[ "$status" == "STANDBY" ]]; then
      out_lines+=("  ${name}: Standby – SMART übersprungen")
    elif [[ "$status" == "SKIP" ]]; then
      out_lines+=("  ${name}: ${detail}")
    else
      out_lines+=("  ${name}: ${detail}")
    fi
  done <<<"$sorted"

  printf '%s\n' "${out_lines[@]}"
}

ushm_check_smart() {
  ushm_smart_defaults
  SMART_LINES=()
  SMART_REPORT=""
  SMART_OK_COUNT=0
  SMART_STANDBY_COUNT=0
  SMART_FAIL_COUNT=0

  if ! ushm_is_true "${USHM_SMART_ENABLED:-true}"; then
    ushm_debug "SMART-Modul deaktiviert (USHM_SMART_ENABLED=false)"
    return 0
  fi

  ushm_info "Prüfe SMART (Scope=${SMART_SCOPE})…"

  if ! command -v smartctl >/dev/null 2>&1; then
    ushm_warn "smartctl nicht gefunden – SMART übersprungen (NerdPack/Package smartmontools)"
    SMART_REPORT="(smartctl fehlt)"
    return 0
  fi

  local targets
  targets=$(ushm_smart_target_list 2>/dev/null) || true
  if [[ -z "$targets" ]]; then
    ushm_warn "Keine Disks für SMART gefunden (SMART_SCOPE=${SMART_SCOPE})"
    SMART_REPORT="(keine Disks)"
    return 0
  fi

  # Sortiert abarbeiten
  targets=$(printf '%s\n' "$targets" | awk -F'\t' '{
    t=tolower($3)
    r=(t=="parity"?1:(t=="data"?2:(t=="cache"?3:9)))
    printf "%d\t%s\n", r, $0
  }' | sort -t$'\t' -k1,1n -k2,2 | cut -f2-)

  local name device typ
  while IFS=$'\t' read -r name device typ; do
    [[ -z "$name" || -z "$device" ]] && continue
    ushm_smart_probe_disk "$name" "$device" "$typ" || true
  done <<<"$targets"

  SMART_REPORT=$(ushm_smart_format_report)
  return 0
}
