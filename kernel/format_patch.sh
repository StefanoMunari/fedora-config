#!/bin/bash
set -euo pipefail

usage()
{
cat <<EOF
Usage: ${0##*/} [-s subsystem] [-v version] -o output.patch [commit|range]

Options:
  -s subsystem    Subject target, e.g. net, net-next
  -v version      Revision number, e.g. 2 for v2
  -o output       Output file; use - for stdout
  -h              Show this help

Examples:
  ${0##*/} -s net -o fix.patch
  ${0##*/} -s net -v 2 -o fix-v2.patch HEAD
  ${0##*/} -s net-next -o series.patch origin/main..HEAD
EOF
}

subsystem=""
version=""
output=""

while getopts ":s:v:o:h" option; do
	case "$option" in
	s) subsystem="$OPTARG" ;;
	v) version="$OPTARG" ;;
	o) output="$OPTARG" ;;
	h)
		usage
		exit 0
		;;
	:)
		printf 'Missing argument for -%s\n' "$OPTARG" >&2
		exit 1
		;;
	\?)
		printf 'Unknown option: -%s\n' "$OPTARG" >&2
		usage >&2
		exit 1
		;;
	esac
done

shift "$((OPTIND - 1))"

if [[ -z "$output" || $# -gt 1 ]]; then
	usage >&2
	exit 1
fi

if [[ -n "$version" && ! "$version" =~ ^[1-9][0-9]*$ ]]; then
	printf 'Version must be a positive integer\n' >&2
	exit 1
fi

ref="${1:-HEAD}"
prefix="PATCH"

if [[ -n "$subsystem" ]]; then
	prefix+=" $subsystem"
fi

args=(
	"--subject-prefix=$prefix"
	--no-to
	--no-cc
	--no-thread
	--stdout
)

if [[ -n "$version" ]]; then
	args+=("--reroll-count=$version")
fi

if [[ "$ref" == *..* ]]; then
	args+=("$ref")
else
	args+=(-1 "$ref")
fi

if [[ "$output" == "-" ]]; then
	git format-patch "${args[@]}"
else
	git format-patch "${args[@]}" > "$output"
fi
