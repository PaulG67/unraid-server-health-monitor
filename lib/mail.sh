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

  local html
  html="$(ushm_report_html)"

  ushm_info "Sende Mail an $MAIL_TO – $subject"

  if command -v msmtp >/dev/null 2>&1; then
    local tls_args=()
    if ushm_is_true "$SMTP_TLS"; then
      tls_args=(--tls=on --tls-starttls=on)
    fi
    {
      echo "From: $MAIL_FROM"
      echo "To: $MAIL_TO"
      echo "Subject: $subject"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/html; charset=UTF-8"
      echo
      echo "$html"
    } | msmtp --host="$SMTP_SERVER" --port="$SMTP_PORT" \
        "${tls_args[@]}" \
        ${SMTP_USER:+--user="$SMTP_USER"} \
        --from="$MAIL_FROM" \
        "$MAIL_TO"
    return $?
  fi

  local py=""
  if command -v python3 >/dev/null 2>&1; then
    py=$(command -v python3)
  elif command -v python >/dev/null 2>&1; then
    py=$(command -v python)
  fi

  if [[ -n "$py" ]]; then
    export SMTP_SERVER SMTP_PORT SMTP_USER SMTP_PASS SMTP_TLS MAIL_FROM MAIL_TO
    export USHM_MAIL_SUBJECT="$subject"
    export USHM_MAIL_HTML="$html"
    "$py" - <<'PY'
import os, smtplib, ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

server = os.environ.get("SMTP_SERVER", "")
port = int(os.environ.get("SMTP_PORT", "587"))
user = os.environ.get("SMTP_USER", "")
password = os.environ.get("SMTP_PASS", "")
mail_from = os.environ.get("MAIL_FROM", "")
mail_to = os.environ.get("MAIL_TO", "")
tls = os.environ.get("SMTP_TLS", "true").lower() in ("1", "true", "yes", "on")
subject = os.environ["USHM_MAIL_SUBJECT"]
html = os.environ["USHM_MAIL_HTML"]

msg = MIMEMultipart("alternative")
msg["Subject"] = subject
msg["From"] = mail_from
msg["To"] = mail_to
msg.attach(MIMEText(html, "html", "utf-8"))

recipients = [a.strip() for a in mail_to.split(",") if a.strip()]

if tls:
    context = ssl.create_default_context()
    with smtplib.SMTP(server, port, timeout=30) as s:
        s.ehlo()
        s.starttls(context=context)
        s.ehlo()
        if user:
            s.login(user, password)
        s.sendmail(mail_from, recipients, msg.as_string())
else:
    with smtplib.SMTP(server, port, timeout=30) as s:
        if user:
            s.login(user, password)
        s.sendmail(mail_from, recipients, msg.as_string())
print("mail ok")
PY
    return $?
  fi

  ushm_error "Weder msmtp noch python für Mail-Versand verfügbar"
  return 1
}
