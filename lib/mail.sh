#!/usr/bin/env bash
# SMTP HTML-Mail Versand (msmtp oder Python)
# shellcheck disable=SC2034

ushm_send_mail() {
  [[ -n "$SMTP_SERVER" && -n "$MAIL_TO" && -n "$MAIL_FROM" ]] || {
    ushm_warn "Mail: SMTP_SERVER / MAIL_FROM / MAIL_TO unvollständig"
    return 1
  }

  local subject host emoji
  host="$(ushm_hostname)"
  emoji="$(ushm_severity_emoji)"
  subject="${emoji} USHM [${host}] $(ushm_severity_label)"

  local html_file
  html_file=$(mktemp)
  ushm_report_html >"$html_file"

  ushm_info "Sende Mail an $MAIL_TO – $subject (${SMTP_SERVER}:${SMTP_PORT})"

  local rc=1
  if command -v msmtp >/dev/null 2>&1; then
    ushm_send_mail_msmtp "$subject" "$html_file"
    rc=$?
  else
    local py=""
    if command -v python3 >/dev/null 2>&1; then
      py=$(command -v python3)
    elif command -v python >/dev/null 2>&1; then
      py=$(command -v python)
    fi
    if [[ -n "$py" ]]; then
      ushm_send_mail_python "$py" "$subject" "$html_file"
      rc=$?
    else
      ushm_error "Weder msmtp noch python für Mail-Versand verfügbar"
      rc=1
    fi
  fi

  rm -f "$html_file"
  return "$rc"
}

ushm_send_mail_msmtp() {
  local subject="$1" html_file="$2"
  local tls_args=()
  if ushm_is_true "${SMTP_SSL:-false}" || [[ "${SMTP_PORT}" == "465" ]]; then
    tls_args=(--tls=on --tls-starttls=off)
  elif ushm_is_true "$SMTP_TLS"; then
    tls_args=(--tls=on --tls-starttls=on)
  fi
  {
    echo "From: $MAIL_FROM"
    echo "To: $MAIL_TO"
    echo "Subject: $subject"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo
    cat "$html_file"
  } | msmtp --host="$SMTP_SERVER" --port="$SMTP_PORT" \
      "${tls_args[@]}" \
      ${SMTP_USER:+--user="$SMTP_USER"} \
      --from="$MAIL_FROM" \
      "$MAIL_TO"
}

ushm_send_mail_python() {
  local py="$1" subject="$2" html_file="$3"
  local retries="${SMTP_RETRIES:-3}"
  local timeout="${SMTP_TIMEOUT:-60}"

  export SMTP_SERVER SMTP_PORT SMTP_USER SMTP_PASS SMTP_TLS SMTP_SSL
  export MAIL_FROM MAIL_TO
  export USHM_MAIL_SUBJECT="$subject"
  export USHM_MAIL_HTML_FILE="$html_file"
  export USHM_SMTP_RETRIES="$retries"
  export USHM_SMTP_TIMEOUT="$timeout"

  "$py" - <<'PY'
import os, smtplib, ssl, sys, time
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

server = os.environ.get("SMTP_SERVER", "")
port = int(os.environ.get("SMTP_PORT", "587"))
user = os.environ.get("SMTP_USER", "")
password = os.environ.get("SMTP_PASS", "")
mail_from = os.environ.get("MAIL_FROM", "")
mail_to = os.environ.get("MAIL_TO", "")
tls = os.environ.get("SMTP_TLS", "true").lower() in ("1", "true", "yes", "on")
ssl_mode = os.environ.get("SMTP_SSL", "false").lower() in ("1", "true", "yes", "on") or port == 465
subject = os.environ["USHM_MAIL_SUBJECT"]
html_file = os.environ["USHM_MAIL_HTML_FILE"]
retries = max(1, int(os.environ.get("USHM_SMTP_RETRIES", "3")))
timeout = int(os.environ.get("USHM_SMTP_TIMEOUT", "60"))

with open(html_file, "r", encoding="utf-8") as f:
    html = f.read()

msg = MIMEMultipart("alternative")
msg["Subject"] = subject
msg["From"] = mail_from
msg["To"] = mail_to
msg.attach(MIMEText(html, "html", "utf-8"))
recipients = [a.strip() for a in mail_to.split(",") if a.strip()]
payload = msg.as_string()
context = ssl.create_default_context()

def send_once():
    if ssl_mode:
        with smtplib.SMTP_SSL(server, port, timeout=timeout, context=context) as s:
            if user:
                s.login(user, password)
            s.sendmail(mail_from, recipients, payload)
        return
    with smtplib.SMTP(server, port, timeout=timeout) as s:
        s.ehlo()
        if tls:
            s.starttls(context=context)
            s.ehlo()
        if user:
            s.login(user, password)
        s.sendmail(mail_from, recipients, payload)

last_err = None
for attempt in range(1, retries + 1):
    try:
        send_once()
        print(f"mail ok (attempt {attempt}/{retries})", flush=True)
        sys.exit(0)
    except Exception as e:
        last_err = e
        print(f"mail attempt {attempt}/{retries} failed: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        if attempt < retries:
            time.sleep(2 * attempt)

print(f"mail failed after {retries} attempts: {last_err}", file=sys.stderr, flush=True)
print("Tipp: Port 587 + SMTP_TLS=true (STARTTLS) oder Port 465 + SMTP_SSL=true", file=sys.stderr, flush=True)
sys.exit(1)
PY
}
