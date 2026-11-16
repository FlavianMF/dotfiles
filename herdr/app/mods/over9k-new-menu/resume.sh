#!/bin/sh
# Starts an agent on a model, or resumes its session on the model it ran on:
# resume.sh <agent> <id, or "" for a new session> [model] [provider] [first message].
# A model that isn't the agent's own (a local one, say) is looked up in Pi's model
# list (~/.pi/agent/models.json): the provider that has it says where its server is.
# A server on this computer that isn't answering is started first, with the command
# servers.json (next to this script) gives for its address ({start, stop}; the
# sidebar's chip for a running server uses stop), and waited for.
# servers.json: {"http://127.0.0.1:8081": {"start": "<command>", "stop": "<command>"}}
# (address = the provider's baseUrl without /v1; a plain string means start only).
# Everything optional: without Pi's list, jq or curl, agents start on their own model.
agent=$1 id=$2 model=$3 provider=$4 asked=$4 first=${5:-}
here=$(dirname "$(readlink -f "$0" 2>/dev/null || printf %s "$0")")
models="$HOME/.pi/agent/models.json"     # Pi's model list (providers: baseUrl, apiKey, models)
codex_config="$HOME/.codex/config.toml"  # Codex's [model_providers.<name>] base_url
server_log="${XDG_CACHE_HOME:-$HOME/.cache}/herdr-servers.log"

# The Codex provider (config.toml's [model_providers.<name>]) whose base_url is $1.
codex_provider() {
  awk -v want="$1" '
    /^\[model_providers\./ { name = $0; sub(/^\[model_providers\./, "", name); sub(/\].*/, "", name); gsub(/"/, "", name); next }
    /^\[/ { name = "" }
    name != "" && /^[ \t]*base_url[ \t]*=/ {
      v = $0; sub(/^[^=]*=[ \t]*"/, "", v); sub(/".*/, "", v); sub(/\/+$/, "", v); w = want; sub(/\/+$/, "", w)
      if (v == w) { print name; exit }
    }' "$codex_config" 2>/dev/null
}

# Where the model's server is: base URL, key and context size, from Pi's list
# (the provider named, else any that has the model: Codex names providers its own way).
base="" key="" ctx=""
if [ -n "$model" ] && [ -f "$models" ] && command -v jq >/dev/null 2>&1; then
  found=$(jq -r --arg m "$model" --arg p "$provider" '[.providers // {} | to_entries[]
    | select(any(.value.models[]?; .id == $m))] | (map(select(.key == $p)) + .)[:1][]
    | [.key, .value.baseUrl, (.value.apiKey // "none"), ((.value.models[] | select(.id == $m) | .contextWindow) // "")] | @tsv' "$models" 2>/dev/null)
  if [ -n "$found" ]; then
    tab=$(printf '\t')
    IFS="$tab" read -r provider base key ctx <<EOF
$found
EOF
  fi
fi

# Off and on this computer: start it with servers.json's command for its address.
case "$base" in
  http://127.0.0.1:*|http://localhost:*)
    if command -v curl >/dev/null 2>&1 && ! curl -sf -m 2 "$base/models" >/dev/null 2>&1; then
      root=$(printf %s "$base" | sed 's#/v1/*$##')
      start=$(jq -r --arg r "$root" '.[$r] | if type == "object" then .start else . end // empty' "$here/servers.json" 2>/dev/null)
      if [ -n "$start" ]; then
        log=$server_log
        mkdir -p "$(dirname "$log")" 2>/dev/null
        printf 'Starting the server for %s (log: %s)…\n' "$model" "$log"
        # Its own session, so it outlives this terminal (macOS has no setsid).
        if command -v setsid >/dev/null 2>&1; then setsid sh -c "$start" >>"$log" 2>&1 </dev/null &
        else nohup sh -c "$start" >>"$log" 2>&1 </dev/null & fi
        n=0
        until curl -sf -m 2 "$base/models" >/dev/null 2>&1; do
          n=$((n + 1))
          [ "$n" -ge 180 ] && { printf 'The server did not answer after 3 minutes; see %s\n' "$log"; break; }
          sleep 1
        done
      else
        printf 'The server for %s (%s) is off, and servers.json has no command to start it.\n' "$model" "$root"
      fi
    fi ;;
esac

case "$agent" in
  claude)
    # On a server of its own: Claude Code talks to it instead of Anthropic.
    if [ -n "$base" ]; then
      export ANTHROPIC_BASE_URL="$(printf %s "$base" | sed 's#/v1/*$##')" ANTHROPIC_AUTH_TOKEN="$key"
      export ANTHROPIC_MODEL="$model" ANTHROPIC_DEFAULT_OPUS_MODEL="$model" ANTHROPIC_DEFAULT_SONNET_MODEL="$model"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model" CLAUDE_CODE_SUBAGENT_MODEL="$model" API_TIMEOUT_MS=600000
      [ -n "$ctx" ] && export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$ctx"
      unset ANTHROPIC_API_KEY
    fi
    [ -n "$id" ] && exec claude --resume "$id"
    exec claude ${first:+"$first"} ;;
  codex)
    # Its own provider for that server, else the one the session named.
    cp=""; [ -n "$base" ] && cp=$(codex_provider "$base")
    [ -n "$cp" ] || cp=$asked
    set -- ${id:+resume}
    if [ -n "$cp" ] && [ "$cp" != openai ]; then set -- "$@" -c "model_provider=\"$cp\"" -m "$model"; fi
    # A model Codex doesn't know: tell it the context size from Pi's list.
    [ -n "$base" ] && [ -n "$ctx" ] && set -- "$@" -c "model_context_window=$ctx"
    exec codex "$@" ${id:+"$id"} ${first:+"$first"} ;;
  pi)
    set -- ${id:+--session "$id"}
    if [ -n "$model" ] && [ -n "$provider" ]; then set -- "$@" --model "$provider/$model"; fi
    exec pi "$@" ${first:+"$first"} ;;
  antigravity)
    [ -n "$id" ] && exec agy --conversation "$id"
    exec agy ${first:+-i "$first"} ;;
esac
printf 'No way to start a %s session.\n' "$agent"
