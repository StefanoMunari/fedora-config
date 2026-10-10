#!/bin/bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $0 \"Full Name\" \"email\"" >&2; exit 1; }

name=$1
email=$2
domain=${email##*@}

case "${domain,,}" in
    gmail.com | googlemail.com) smtp_server=smtp.gmail.com ;;
    *) echo "Unsupported email domain: $domain" >&2; exit 1 ;;
esac

git config --local sendemail.from "$name <$email>"
git config --local sendemail.smtpServer "$smtp_server"
git config --local sendemail.smtpServerPort 587
git config --local sendemail.smtpEncryption tls
git config --local sendemail.smtpUser "$email"
git config --local sendemail.confirm always
