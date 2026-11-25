#!/bin/sh
NOT_INSTALLED=127
NO_REPLY=1
WAIT_ROUNDS=75
REQUEST='{"type":"control_request","request_id":"herdr-usage-limits","request":{"subtype":"get_usage","skip_behaviors":true}}'

CLAUDE=$(command -v "${HERDR_USAGE_CLAUDE_BIN:-claude}" 2>/dev/null) || exit "$NOT_INSTALLED"
DEFAULT_DIR="${CLAUDE_DEFAULT_DIR:-$HOME/.claude}"
PROFILES_DIR="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"

query_profile() {
  profile=$1
  cfg_dir=$2
  dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-claude-usage.XXXXXX") || return 1
  out="$dir/out"

  printf '%s\n' "$REQUEST" >"$dir/in"
  if [ -n "$cfg_dir" ]; then
    CLAUDE_CONFIG_DIR="$cfg_dir" "$CLAUDE" -p --safe-mode --no-session-persistence \
      --input-format stream-json --output-format stream-json --verbose \
      <"$dir/in" >"$out" 2>/dev/null &
  else
    env -u CLAUDE_CONFIG_DIR "$CLAUDE" -p --safe-mode --no-session-persistence \
      --input-format stream-json --output-format stream-json --verbose \
      <"$dir/in" >"$out" 2>/dev/null &
  fi
  pid=$!

  i=0
  while [ "$i" -lt "$WAIT_ROUNDS" ]; do
    if grep -q '"control_response"' "$out" 2>/dev/null; then break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
    i=$((i + 1))
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  line=$(grep -m1 '"control_response"' "$out" 2>/dev/null || true)
  rm -rf "$dir"
  [ -n "$line" ] || return 1
  printf '{"profile":"%s","reply":%s}\n' "$profile" "$line"
  return 0
}

queried=0
emitted=0

if [ -f "$DEFAULT_DIR/.credentials.json" ] || [ ! -d "$PROFILES_DIR" ]; then
  queried=1
  if query_profile "default" ""; then
    emitted=$((emitted + 1))
  fi
fi

if [ -d "$PROFILES_DIR" ]; then
  for p in "$PROFILES_DIR"/*; do
    [ -d "$p" ] || continue
    [ -f "$p/.credentials.json" ] || continue
    queried=1
    if query_profile "$(basename "$p")" "$p"; then
      emitted=$((emitted + 1))
    fi
  done
fi

if [ "$queried" -eq 0 ]; then
  if query_profile "default" ""; then
    emitted=$((emitted + 1))
  fi
fi

[ "$emitted" -gt 0 ] && exit 0
exit "$NO_REPLY"
