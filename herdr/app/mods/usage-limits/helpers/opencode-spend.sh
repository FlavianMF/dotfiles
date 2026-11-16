#!/bin/sh
NOT_INSTALLED=127
NO_READING=1
DEADLINE_ROUNDS=50
TERM_GRACE_ROUNDS=5
db=${HERDR_USAGE_OPENCODE_DB:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db}
if [ -z "${HERDR_USAGE_OPENCODE_BIN:-}" ] && [ -f "$db" ]; then
  exec sh "$(dirname "$0")/opencode-db.sh" spend "$db"
fi
OC=$(command -v "${HERDR_USAGE_OPENCODE_BIN:-opencode}" 2>/dev/null) || exit "$NOT_INSTALLED"

dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-opencode-spend.XXXXXX") || exit 1
trap 'rm -rf "$dir"' EXIT

"$OC" stats --days 0 --json </dev/null >"$dir/today" 2>/dev/null &
p1=$!
"$OC" stats --days 7 --json </dev/null >"$dir/week" 2>/dev/null &
p2=$!

either_running() { kill -0 "$p1" 2>/dev/null || kill -0 "$p2" 2>/dev/null; }

term_then_kill_after_grace() {
  kill "$p1" "$p2" 2>/dev/null
  j=0
  while [ "$j" -lt "$TERM_GRACE_ROUNDS" ] && either_running; do
    sleep 0.2
    j=$((j + 1))
  done
  kill -9 "$p1" "$p2" 2>/dev/null
  wait "$p1" "$p2" 2>/dev/null
}

i=0
while either_running; do
  if [ "$i" -ge "$DEADLINE_ROUNDS" ]; then
    term_then_kill_after_grace
    exit "$NO_READING"
  fi
  sleep 0.2
  i=$((i + 1))
done
wait "$p1" || exit "$NO_READING"
wait "$p2" || exit "$NO_READING"

from_first_json_line() { sed -n '/^{/,$p' "$1" | tr -d '\r\n'; }

today=$(from_first_json_line "$dir/today")
week=$(from_first_json_line "$dir/week")
for v in "$today" "$week"; do
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  case "$v" in
    "{"*"}") ;;
    *) exit "$NO_READING" ;;
  esac
done
printf '{"today":%s,"week":%s}\n' "$today" "$week"
