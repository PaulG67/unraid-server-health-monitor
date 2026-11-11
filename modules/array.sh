#!/usr/bin/env bash
# Array / Disk-Inventar + Parity/Data I/O (parity, parity2, diskN, Cache)
# Quelle: /var/local/emhttp/disks.ini + var.ini
# shellcheck disable=SC2034

# Ergebnisse:
# PARITY_* Arrays, DISK_* Übersicht, DISK_INVENTORY_REPORT
# PARITY_REPORT  ARRAY_MD_STATE  ARRAY_SYNC_ERRS  ARRAY_RESYNC

ushm_array_defaults() {
  USHM_ARRAY_ENABLED="${USHM_ARRAY_ENABLED:-true}"
  USHM_INVENTORY_ENABLED="${USHM_INVENTORY_ENABLED:-true}"
  PARITY_ERROR_WARN="${PARITY_ERROR_WARN:-1}"
  PARITY_ERROR_CRIT="${PARITY_ERROR_CRIT:-1}"
  # Data-Disks: gleiche I/O-Schwellwerte (numErrors)
  DISK_ERROR_WARN="${DISK_ERROR_WARN:-${PARITY_ERROR_WARN}}"
  DISK_ERROR_CRIT="${DISK_ERROR_CRIT:-${PARITY_ERROR_CRIT}}"
}

# Alle Nicht-Flash-Disks: name\ttype\tdevice\tstatus\tnumErrors\ttemp\tcolor\tid
ushm_array_list_disks() {
  local ini="${1:-/var/local/emhttp/disks.ini}"
  [[ -f "$ini" ]] || return 1
  awk '
    /^\[/ {
      if (sec != "" && tolower(typ) != "flash" && (device != "" || tolower(typ) == "parity" || tolower(typ) == "data" || tolower(typ) == "cache")) {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          (name!=""?name:sec), typ, device, status, errors, temp, color, id
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
      if (sec != "" && tolower(typ) != "flash" && (device != "" || tolower(typ) == "parity" || tolower(typ) == "data" || tolower(typ) == "cache")) {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
          (name!=""?name:sec), typ, device, status, errors, temp, color, id
      }
    }
  ' "$ini"
}

# Nur Parity: name\tdevice\tstatus\tnumErrors\ttemp\tcolor\tid
ushm_array_list_parity() {
  ushm_array_list_disks "$@" | awk -F'\t' 'tolower($2)=="parity" {
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1,$3,$4,$5,$6,$7,$8
  }'
}

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

# Inventar: hinzugekommen / entfernt / ersetzt (gleicher Slot, andere ID)
ushm_check_disk_inventory() {
  DISK_INVENTORY_REPORT=""
  DISK_INVENTORY_ADDED=()
  DISK_INVENTORY_REMOVED=()
  DISK_INVENTORY_REPLACED=()
  DISK_COUNT=0

  if ! ushm_is_true "${USHM_INVENTORY_ENABLED:-true}"; then
    ushm_debug "Disk-Inventar deaktiviert"
    return 0
  fi

  if [[ ! -f /var/local/emhttp/disks.ini ]]; then
    DISK_INVENTORY_REPORT="(keine Unraid disks.ini)"
    return 0
  fi

  ushm_info "Prüfe Disk-Inventar (Vollständigkeit)…"

  local inv_file cur_file
  inv_file=$(ushm_state_file "disk_inventory")
  cur_file="${DATA_DIR}/state/disk_inventory.current.$$"
  ushm_mkdir_p "$(dirname "$inv_file")"

  local name typ device status errors temp color id
  local list
  list=$(ushm_array_list_disks) || true
  : >"$cur_file"

  while IFS=$'\t' read -r name typ device status errors temp color id; do
    [[ -z "$name" ]] && continue
    # name|type|device|id
    printf '%s|%s|%s|%s\n' "$name" "$typ" "${device:-}" "${id:-}" >>"$cur_file"
    DISK_COUNT=$(( DISK_COUNT + 1 ))
  done <<<"$list"

  # Stabil sortieren für Diff
  if [[ -s "$cur_file" ]]; then
    sort -t'|' -k1,1 -o "$cur_file" "$cur_file"
  fi

  local lines=()
  lines+=("Disks im Array/Pools: ${DISK_COUNT}")

  if [[ ! -f "$inv_file" ]]; then
    lines+=("Baseline gespeichert (erster Inventar-Lauf)")
    cp -f "$cur_file" "$inv_file"
    DISK_INVENTORY_REPORT=$(printf '%s\n' "${lines[@]}")
    ushm_info "Disk-Inventar: ${DISK_COUNT} Disks (Baseline)"
    rm -f "$cur_file"
    return 0
  fi

  # Index vorheriger Inventar-Einträge: name → type|device|id
  declare -A prev_map=()
  local row p_name p_rest
  while IFS= read -r row; do
    [[ -z "$row" || "$row" == \#* ]] && continue
    p_name="${row%%|*}"
    p_rest="${row#*|}"
    [[ -n "$p_name" ]] && prev_map["$p_name"]="$p_rest"
  done <"$inv_file"

  declare -A cur_map=()
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    p_name="${row%%|*}"
    p_rest="${row#*|}"
    [[ -n "$p_name" ]] && cur_map["$p_name"]="$p_rest"
  done <"$cur_file"

  local n
  for n in "${!cur_map[@]}"; do
    if [[ -z "${prev_map[$n]+x}" ]]; then
      DISK_INVENTORY_ADDED+=("$n (${cur_map[$n]%%|*})")
      ushm_add_alert 1 "Inventar" "Disk hinzugekommen: ${n} (${cur_map[$n]%%|*})"
    else
      local prev_id cur_id
      prev_id="${prev_map[$n]##*|}"
      cur_id="${cur_map[$n]##*|}"
      if [[ -n "$prev_id" && -n "$cur_id" && "$prev_id" != "$cur_id" ]]; then
        DISK_INVENTORY_REPLACED+=("$n ($prev_id → $cur_id)")
        ushm_add_alert 2 "Inventar" "Disk ersetzt: ${n} (ID ${prev_id} → ${cur_id})"
      fi
    fi
  done

  for n in "${!prev_map[@]}"; do
    if [[ -z "${cur_map[$n]+x}" ]]; then
      DISK_INVENTORY_REMOVED+=("$n (${prev_map[$n]%%|*})")
      ushm_add_alert 2 "Inventar" "Disk fehlt / entfernt: ${n} (${prev_map[$n]%%|*})"
    fi
  done

  if (( ${#DISK_INVENTORY_ADDED[@]} == 0 && ${#DISK_INVENTORY_REMOVED[@]} == 0 && ${#DISK_INVENTORY_REPLACED[@]} == 0 )); then
    lines+=("Vollständig – keine Änderungen seit letztem Lauf")
  else
    (( ${#DISK_INVENTORY_ADDED[@]} > 0 )) && lines+=("Hinzugekommen: ${DISK_INVENTORY_ADDED[*]}")
    (( ${#DISK_INVENTORY_REMOVED[@]} > 0 )) && lines+=("Entfernt/fehlt: ${DISK_INVENTORY_REMOVED[*]}")
    (( ${#DISK_INVENTORY_REPLACED[@]} > 0 )) && lines+=("Ersetzt: ${DISK_INVENTORY_REPLACED[*]}")
  fi

  cp -f "$cur_file" "$inv_file"
  rm -f "$cur_file"

  DISK_INVENTORY_REPORT=$(printf '%s\n' "${lines[@]}")
  ushm_info "Disk-Inventar: ${DISK_COUNT} Disks · +${#DISK_INVENTORY_ADDED[@]} −${#DISK_INVENTORY_REMOVED[@]} ↔${#DISK_INVENTORY_REPLACED[@]}"
  return 0
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
  DISK_OVERVIEW_REPORT=""
  ARRAY_MD_STATE=""
  ARRAY_SYNC_ERRS=""
  ARRAY_RESYNC=""

  # Inventar immer zuerst (auch wenn Array-I/O aus)
  ushm_check_disk_inventory || true

  if ! ushm_is_true "${USHM_ARRAY_ENABLED:-true}"; then
    ushm_debug "Array/Parity-Modul deaktiviert (USHM_ARRAY_ENABLED=false)"
    PARITY_REPORT="${DISK_INVENTORY_REPORT:-(Inventar aus)}"
    return 0
  fi

  ushm_info "Prüfe Array / alle Disks…"

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
  list=$(ushm_array_list_disks) || true
  if [[ -z "$list" ]]; then
    ushm_warn "Keine Disks in disks.ini gefunden"
    PARITY_REPORT="${DISK_INVENTORY_REPORT}"$'\n'"(keine Disks)"
    return 0
  fi

  # Nach Typ + Name sortieren
  list=$(printf '%s\n' "$list" | awk -F'\t' '{
    t=tolower($2)
    r=(t=="parity"?1:(t=="data"?2:(t=="cache"?3:9)))
    printf "%d\t%s\n", r, $0
  }' | sort -t$'\t' -k1,1n -k2,2 | cut -f2-)

  local header_lines=()
  header_lines+=("Array: ${ARRAY_MD_STATE:-?} · SyncErrs: ${ARRAY_SYNC_ERRS}${ARRAY_RESYNC:+ · ${ARRAY_RESYNC}}")
  if [[ -n "${DISK_INVENTORY_REPORT:-}" ]]; then
    local iline
    while IFS= read -r iline; do
      [[ -n "$iline" ]] && header_lines+=("$iline")
    done <<<"$DISK_INVENTORY_REPORT"
  fi

  local section_lines=()
  local cur_section=""
  local name typ device status errors temp color id

  while IFS=$'\t' read -r name typ device status errors temp color id; do
    [[ -z "$name" ]] && continue
    [[ -z "$errors" || ! "$errors" =~ ^[0-9]+$ ]] && errors=0

    local typ_l="${typ,,}"
    local section_label
    case "$typ_l" in
      parity) section_label="Parity" ;;
      data)   section_label="Data" ;;
      cache)  section_label="Cache" ;;
      *)      section_label="${typ:-Other}" ;;
    esac

    if [[ "$section_label" != "$cur_section" ]]; then
      cur_section="$section_label"
      section_lines+=("")
      section_lines+=("--- ${section_label} ---")
    fi

    local state_key="diskio_${name}"
    local state_file prev delta have_prev=0
    state_file=$(ushm_state_file "$state_key")
    # Legacy: Parity nutzte parity_<name>
    if [[ "$typ_l" == "parity" && ! -f "$state_file" ]]; then
      local legacy
      legacy=$(ushm_state_file "parity_${name}")
      [[ -f "$legacy" ]] && state_file="$legacy"
    fi

    if [[ -f "$state_file" ]]; then
      have_prev=1
      prev=$(ushm_state_get "$state_file" "numErrors")
    else
      prev=0
    fi
    [[ -z "$prev" || ! "$prev" =~ ^[0-9]+$ ]] && prev=0
    delta=$(( errors - prev ))
    (( delta < 0 )) && delta=0
    (( have_prev == 0 )) && delta=0

    # State immer unter diskio_* speichern (einheitlich)
    local save_file
    save_file=$(ushm_state_file "diskio_${name}")
    ushm_state_set_many "$save_file" \
      "numErrors=${errors}" \
      "status=${status}" \
      "device=${device}" \
      "type=${typ}" \
      "temp=${temp}" \
      "id=${id}" \
      "timestamp=$(date -Iseconds)"

    local delta_txt=""
    if (( have_prev == 0 )); then
      delta_txt="  (Baseline)"
    elif (( delta > 0 )); then
      delta_txt="  [+${delta}]"
    elif (( errors > 0 )); then
      delta_txt="  (=)"
    fi

    local dev_txt="${device:-—}"
    local temp_txt="${temp:-?}"
    section_lines+=("  ${name}: ${status:-?}  I/O=${errors}${delta_txt}  T=${temp_txt}°C  /dev/${dev_txt}")

    # Parity-Arrays für Historie / SMART-Fallback
    if [[ "$typ_l" == "parity" ]]; then
      PARITY_NAMES+=("$name")
      PARITY_DEVICES+=("$device")
      PARITY_STATUS+=("$status")
      PARITY_ERRORS+=("$errors")
      PARITY_DELTA_ERRORS+=("$delta")
      PARITY_TEMP+=("${temp:-?}")
      PARITY_COLOR+=("${color:-}")
      PARITY_ID+=("${id:-}")
    fi

    local cat_label="Disk"
    [[ "$typ_l" == "parity" ]] && cat_label="Parity"
    [[ "$typ_l" == "cache" ]] && cat_label="Cache"

    case "${status^^}" in
      DISK_DSBL|DISK_DSBL_NP|DISK_NP|DISK_INVALID|DISK_WRONG)
        ushm_add_alert 2 "$cat_label" "${name}: Status ${status} – Disk ersetzen/prüfen"
        ;;
    esac
    if [[ "${color,,}" == *"red"* ]]; then
      ushm_add_alert 2 "$cat_label" "${name}: Unraid meldet rot (color=${color})"
    fi

    local warn_th crit_th
    if [[ "$typ_l" == "parity" ]]; then
      warn_th=$PARITY_ERROR_WARN
      crit_th=$PARITY_ERROR_CRIT
    else
      warn_th=$DISK_ERROR_WARN
      crit_th=$DISK_ERROR_CRIT
    fi

    if (( have_prev == 1 )) && (( errors >= crit_th )) && (( delta > 0 )); then
      ushm_add_alert 2 "$cat_label" "${name}: I/O-Fehler gestiegen (+${delta} → ${errors})"
    elif (( errors >= warn_th )); then
      if (( have_prev == 1 )) && (( delta > 0 )); then
        ushm_add_alert 1 "$cat_label" "${name}: I/O-Fehler +${delta} (jetzt ${errors})"
      else
        ushm_add_alert 1 "$cat_label" "${name}: ${errors} I/O-Fehler (numErrors)"
      fi
    fi

    ushm_debug "${typ} ${name}: errors=${errors} delta=+${delta} status=${status}"
  done <<<"$list"

  PARITY_REPORT=$(printf '%s\n' "${header_lines[@]}" "${section_lines[@]}")
  DISK_OVERVIEW_REPORT="$PARITY_REPORT"
  return 0
}
