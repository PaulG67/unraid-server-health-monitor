#!/usr/bin/env bash
# Array / Parity Monitoring (parity + parity2, …)
# Quelle: /var/local/emhttp/disks.ini + var.ini
# shellcheck disable=SC2034

# Ergebnisse:
# PARITY_NAMES[] PARITY_DEVICES[] PARITY_STATUS[] PARITY_ERRORS[]
# PARITY_DELTA_ERRORS[] PARITY_TEMP[] PARITY_COLOR[] PARITY_ID[]
# PARITY_REPORT  ARRAY_MD_STATE  ARRAY_SYNC_ERRS  ARRAY_RESYNC

ushm_array_defaults() {
  USHM_ARRAY_ENABLED="${USHM_ARRAY_ENABLED:-true}"
  PARITY_ERROR_WARN="${PARITY_ERROR_WARN:-1}"   # Warnung ab so vielen numErrors
  PARITY_ERROR_CRIT="${PARITY_ERROR_CRIT:-1}"   # Kritisch wenn Delta ≥ oder absolute ≥
}

# Listet Parity-Disks: name\tdevice\tstatus\tnumErrors\ttemp\tcolor\tid
ushm_array_list_parity() {
  local ini="${1:-/var/local/emhttp/disks.ini}"
  [[ -f "$ini" ]] || return 1
  awk '
    /^\[/ {
      if (sec != "" && tolower(typ) == "parity") {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          (name!=""?name:sec), device, status, errors, temp, color, id
      }
      s=$0; gsub(/^\[|\]$/, "", s)
      sec=s; typ=""; name=""; device=""; status=""; errors="0"; temp=""; color=""; id=""
      next
    }
    {
      line=$0; gsub(/\r/, "", line)
      if (line ~ /^type=/)   { typ=line;  sub(/^type=/,"",typ);  gsub(/^"|"$/,"",typ) }
      if (line ~ /^name=/)   { name=line; sub(/^name=/,"",name); gsub(/^"|"$/,"",name) }
      if (line ~ /^device=/) { device=line; sub(/^device=/,"",device); gsub(/^"|"$/,"",device) }
      if (line ~ /^status=/) { status=line; sub(/^status=/,"",status); gsub(/^"|"$/,"",status) }
      if (line ~ /^numErrors=/) { errors=line; sub(/^numErrors=/,"",errors); gsub(/^"|"$/,"",errors) }
      if (line ~ /^temp=/)   { temp=line; sub(/^temp=/,"",temp); gsub(/^"|"$/,"",temp) }
      if (line ~ /^color=/)  { color=line; sub(/^color=/,"",color); gsub(/^"|"$/,"",color) }
      if (line ~ /^id=/)     { id=line; sub(/^id=/,"",id); gsub(/^"|"$/,"",id) }
    }
    END {
      if (sec != "" && tolower(typ) == "parity") {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          (name!=""?name:sec), device, status, errors, temp, color, id
      }
    }
  ' "$ini"
}

ushm_array_var_get() {
  ushm_unraid_ini_get "/var/local/emhttp/var.ini" "var" "$1" 2>/dev/null \
    || ushm_unraid_ini_get "/var/local/emhttp/var.ini" "" "$1" 2>/dev/null \
    || true
}

# var.ini hat oft kein [var]-Section – flache KEY="value" Datei
ushm_array_var_flat() {
  local key="$1"
  local file="/var/local/emhttp/var.ini"
  [[ -f "$file" ]] || { echo ""; return 0; }
  awk -F= -v k="$key" '
    $1 == k {
      val=$0; sub(/^[^=]*=/, "", val)
      gsub(/\r/, "", val); gsub(/^"/, "", val); gsub(/"$/, "", val)
      print val; exit
    }
  ' "$file"
}

ushm_check_array() {
  ushm_array_defaults

  PARITY_NAMES=()
  PARITY_DEVICES=()
  PARITY_STATUS=()
  PARITY_ERRORS=()
  PARITY_DELTA_ERRORS=()
  PARITY_TEMP=()
  PARITY_COLOR=()
  PARITY_ID=()
  PARITY_REPORT=""
  ARRAY_MD_STATE=""
  ARRAY_SYNC_ERRS=""
  ARRAY_RESYNC=""

  if ! ushm_is_true "${USHM_ARRAY_ENABLED:-true}"; then
    ushm_debug "Array/Parity-Modul deaktiviert (USHM_ARRAY_ENABLED=false)"
    return 0
  fi

  ushm_info "Prüfe Parität (Array)…"

  if [[ ! -f /var/local/emhttp/disks.ini ]]; then
    ushm_warn "disks.ini nicht gefunden – Array-Check übersprungen (nicht Unraid?)"
    PARITY_REPORT="(keine Unraid disks.ini)"
    return 0
  fi

  ARRAY_MD_STATE=$(ushm_array_var_flat "mdState")
  ARRAY_SYNC_ERRS=$(ushm_array_var_flat "sbSyncErrs")
  local resync_pos resync_size resync_action
  resync_pos=$(ushm_array_var_flat "mdResyncPos")
  resync_size=$(ushm_array_var_flat "mdResyncSize")
  resync_action=$(ushm_array_var_flat "mdResyncAction")
  if [[ -n "$resync_pos" && -n "$resync_size" && "$resync_size" =~ ^[0-9]+$ && "$resync_size" -gt 0 ]]; then
    local pct=$(( resync_pos * 100 / resync_size ))
    ARRAY_RESYNC="${resync_action:-resync} ${pct}%"
  fi

  [[ -z "$ARRAY_SYNC_ERRS" ]] && ARRAY_SYNC_ERRS=0
  if [[ "$ARRAY_SYNC_ERRS" =~ ^[0-9]+$ ]] && (( ARRAY_SYNC_ERRS > 0 )); then
    ushm_add_alert 2 "Parity" "Parity-Sync-Fehler (sbSyncErrs=${ARRAY_SYNC_ERRS}) – Parität prüfen"
  fi

  local list
  list=$(ushm_array_list_parity) || true
  if [[ -z "$list" ]]; then
    ushm_warn "Keine Parity-Disk in disks.ini gefunden"
    PARITY_REPORT="(keine Parity-Disk)"
    return 0
  fi

  local lines=()
  lines+=("Array: ${ARRAY_MD_STATE:-?} · SyncErrs: ${ARRAY_SYNC_ERRS}${ARRAY_RESYNC:+ · ${ARRAY_RESYNC}}")

  local name device status errors temp color id
  while IFS=$'\t' read -r name device status errors temp color id; do
    [[ -z "$name" ]] && continue
    [[ -z "$errors" || ! "$errors" =~ ^[0-9]+$ ]] && errors=0

    local state_file prev delta have_prev=0
    state_file=$(ushm_state_file "parity_${name}")
    if [[ -f "$state_file" ]]; then
      have_prev=1
      prev=$(ushm_state_get "$state_file" "numErrors")
    else
      prev=0
    fi
    [[ -z "$prev" || ! "$prev" =~ ^[0-9]+$ ]] && prev=0
    delta=$(( errors - prev ))
    (( delta < 0 )) && delta=0
    # Erster Lauf: kein Delta-Alarm (Baseline speichern)
    (( have_prev == 0 )) && delta=0

    PARITY_NAMES+=("$name")
    PARITY_DEVICES+=("$device")
    PARITY_STATUS+=("$status")
    PARITY_ERRORS+=("$errors")
    PARITY_DELTA_ERRORS+=("$delta")
    PARITY_TEMP+=("${temp:-?}")
    PARITY_COLOR+=("${color:-}")
    PARITY_ID+=("${id:-}")

    ushm_state_set_many "$state_file" \
      "numErrors=${errors}" \
      "status=${status}" \
      "device=${device}" \
      "temp=${temp}" \
      "timestamp=$(date -Iseconds)"

    local delta_txt=""
    if (( have_prev == 0 )); then
      delta_txt="  (Baseline gespeichert)"
    elif (( delta > 0 )); then
      delta_txt="  [+${delta} seit letztem Lauf]"
    elif (( errors > 0 )); then
      delta_txt="  (unverändert seit letztem Lauf)"
    fi

    lines+=("${name}: status=${status:-?}  I/O-Errors=${errors}${delta_txt}  temp=${temp:-?}°C  device=${device:-?}")

    # Status: disabled / missing → kritisch
    case "${status^^}" in
      DISK_DSBL|DISK_DSBL_NP|DISK_NP|DISK_INVALID|DISK_WRONG)
        ushm_add_alert 2 "Parity" "${name}: Status ${status} – Disk ersetzen/prüfen"
        ;;
    esac
    if [[ "${color,,}" == *"red"* ]]; then
      ushm_add_alert 2 "Parity" "${name}: Unraid meldet rot (color=${color})"
    fi

    # I/O-Fehler (Unraid numErrors) – getrennt von SMART
    if (( have_prev == 1 )) && (( errors >= PARITY_ERROR_CRIT )) && (( delta > 0 )); then
      ushm_add_alert 2 "Parity" "${name}: I/O-Fehler gestiegen (+${delta} → ${errors}) – Array-Lesefehler"
    elif (( errors >= PARITY_ERROR_WARN )); then
      if (( have_prev == 1 )) && (( delta > 0 )); then
        ushm_add_alert 1 "Parity" "${name}: I/O-Fehler +${delta} (jetzt ${errors})"
      else
        ushm_add_alert 1 "Parity" "${name}: ${errors} I/O-Fehler (numErrors)${have_prev:+ – seit letztem Lauf unverändert}"
      fi
    fi

    ushm_info "Parity ${name}: errors=${errors} delta=+${delta} status=${status}"
  done <<<"$list"

  PARITY_REPORT=$(printf '%s\n' "${lines[@]}")
  return 0
}
