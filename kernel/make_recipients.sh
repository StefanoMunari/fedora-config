#!/bin/bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $0 <path_to_patch> <path_to_output_recipients.txt>" >&2; exit 1; }

patch_file="$1"
recipients_file="$2"

if [ ! -f "$patch_file" ]; then
    echo "Missing/Invalid patch file ('$patch_file')"
    exit 1
fi

perl scripts/get_maintainer.pl \
    --norolestats --noroles \
    $patch_file \
    > $recipients_file

cat $recipients_file
