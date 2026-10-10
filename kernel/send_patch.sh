#!/usr/bin/env bash
set -euo pipefail

## examples:
# ./send_patch.sh dry-run change.patch recipients.txt
# ./send_patch.sh test change.patch
# ./send_patch.sh send change.patch recipients.txt

die() { echo "$*" >&2; exit 1; }

mode=${1:-dry-run}
patch_file=${2:-}
recipients_file=${3:-}

[[ $# -le 3 && -f "$patch_file" && -r "$patch_file" ]] ||
    die "Usage: $0 dry-run|test|send PATCH [RECIPIENTS]"
case "$mode" in dry-run|test|send) ;; *) die "Invalid mode: $mode" ;; esac

from=$(git config --local --get sendemail.from) ||
    die "Missing local sendemail.from"
self=$(git config --local --get sendemail.smtpUser) ||
    die "Missing local sendemail.smtpUser"
[[ -n "$from" && "$self" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] ||
    die "Invalid sender configuration"

# Reject recipient headers; body trailers are allowed.
headers=$(awk '/^\r?$/ { exit } tolower($0) ~ /^(to|cc|bcc):/' "$patch_file")
[[ -z "$headers" ]] || die "Remove To/Cc/Bcc headers from the patch"

if [[ -f scripts/checkpatch.pl ]]; then
    perl scripts/checkpatch.pl "$patch_file"
fi

args=(--no-to --no-cc --no-bcc --to-cmd=true --no-header-cmd
      --suppress-cc=all --no-thread --validate "--from=$from")
recipients=()

if [[ "$mode" == send || ( "$mode" == dry-run && -n "$recipients_file" ) ]]; then
    [[ -f "$recipients_file" && -r "$recipients_file" ]] ||
        die "Missing or unreadable recipient list"

    field=to
    while IFS= read -r address || [[ -n "$address" ]]; do
        address="${address#"${address%%[![:space:]]*}"}"
        address="${address%"${address##*[![:space:]]}"}"
        [[ -z "$address" || "$address" == \#* ]] && continue

        mailbox=$address
        if [[ "$address" == *'<'* && "$address" == *'>' ]]; then
            mailbox=${address##*<}
            mailbox=${mailbox%>}
        fi
        [[ "$address" != -* &&
           "$mailbox" =~ ^[^[:space:]\<\>\,\;@]+@[^[:space:]\<\>\,\;@]+$ ]] ||
            die "Invalid recipient: $address"

        recipients+=("--$field=$address")
        field=cc
    done < "$recipients_file"

    [[ ${#recipients[@]} -gt 0 ]] || die "Empty recipient list"
else
    recipients+=("--to=$self")
fi

case "$mode" in
    dry-run) args+=(--dry-run --confirm=never) ;;
    test|send) args+=(--confirm=always) ;;
esac

printf 'Mode: %s\nPatch: %s\nFrom: %s\n' "$mode" "$patch_file" "$from"
sha256sum -- "$patch_file"
printf 'Recipient: %s\n' "${recipients[@]}"

if [[ "$mode" == send ]]; then
    read -r -p 'Have you completed testing? Type SEND TESTED PATCH: ' confirmation ||
        die "Send cancelled"
    [[ "$confirmation" == 'SEND TESTED PATCH' ]] || die "Send cancelled"
fi

patch_file=$(realpath -- "$patch_file")
exec git -c credential.helper= send-email --no-format-patch \
    "${args[@]}" "${recipients[@]}" "$patch_file"
