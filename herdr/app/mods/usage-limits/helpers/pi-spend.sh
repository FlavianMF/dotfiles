#!/bin/sh
NOT_INSTALLED=127
UNREADABLE=1
dir=${HERDR_USAGE_PI_HOME:-$HOME/.pi}/agent/sessions
awk_dir=$(dirname "$0")/awk
[ -d "$dir" ] || exit "$NOT_INSTALLED"
[ -r "$dir" ] && [ -x "$dir" ] || exit "$UNREADABLE"

replies_in_readable_files() {
  find "$dir/" -type f -name '*.jsonl' -mtime -8 -exec sh -c '
    programs=$1; shift
    for f; do shift; [ -r "$f" ] && set -- "$@" "$f"; done
    [ $# -eq 0 ] || awk -f "$programs/json-field.awk" -f "$programs/pi-replies.awk" "$@"' sh "$awk_dir" {} + 2>/dev/null
}

out=$(replies_in_readable_files)
[ -n "$out" ] || exit 0
printf '%s\n' "$out" | LC_ALL=C sort
