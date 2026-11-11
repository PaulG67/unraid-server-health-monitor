#!/usr/bin/env bash
# Einfache Key=Value State-Dateien unter data/state/
# shellcheck disable=SC2034

ushm_state_file() {
  # $1 = logischer Name → DATA_DIR/state/<name>.env
  local name="$1"
  echo "${DATA_DIR}/state/${name}.env"
}

ushm_state_get() {
  # $1=file $2=key → Wert oder leer
  local file="$1" key="$2"
  [[ -f "$file" ]] || { echo ""; return 0; }
  awk -F= -v k="$key" '
    $1 == k {
      val=$0
      sub(/^[^=]*=/, "", val)
      gsub(/\r/, "", val)
      print val
      exit
    }
  ' "$file"
}

ushm_state_set_many() {
  # $1=file, danach KEY=VALUE Paare
  local file="$1"
  shift
  ushm_mkdir_p "$(dirname "$file")"
  local tmp="${file}.tmp.$$"
  {
    echo "# USHM state $(date -Iseconds)"
    local pair
    for pair in "$@"; do
      echo "$pair"
    done
  } >"$tmp"
  mv -f "$tmp" "$file"
}
