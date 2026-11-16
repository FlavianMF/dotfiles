#!/bin/sh
# Lê os limites do Antigravity (agy) com `/usage` em modo print. Não gasta tokens.
# stream-json devolve o payload estruturado; o modo json às vezes devolve só texto.
NOT_INSTALLED=127
NO_REPLY=1
WAIT_ROUNDS=150

AGY=$(command -v "${HERDR_USAGE_AGY_BIN:-agy}" 2>/dev/null) || exit "$NOT_INSTALLED"

dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-agy-usage.XXXXXX") || exit "$NO_REPLY"
out="$dir/out"
cd "$dir" || exit "$NO_REPLY"

"$AGY" -p "/usage" --output-format stream-json </dev/null >"$out" 2>/dev/null &
pid=$!

i=0
while [ "$i" -lt "$WAIT_ROUNDS" ] && kill -0 "$pid" 2>/dev/null; do
  sleep 0.2
  i=$((i + 1))
done
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

status=$NO_REPLY
if grep -m1 '"command_result"' "$out"; then status=0; fi
cd / && rm -rf "$dir"
exit "$status"
