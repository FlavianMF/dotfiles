#!/bin/sh
# A Claude Code subagent's transcript ($1, a .jsonl), readable and live: what it
# says, each tool it calls (one line), and the start of each result. Over9k
# opens it in a peek over the tab when a subagent row is clicked.
printf '\033]0;%s\007' "Subagent: $(jq -r '.description // "subagent"' "${1%.jsonl}.meta.json" 2>/dev/null)"
tail -n +1 -F "$1" 2>/dev/null | jq -r --unbuffered '
  select(.type == "assistant" or .type == "user") | .message.content
  | if type == "string" then (if startswith("<") or startswith("[SYSTEM") then empty else "\n\u001b[1m› " + . + "\u001b[0m" end)
    else .[] |
      if .type == "text" then "\n" + .text
      elif .type == "tool_use" then "\u001b[36m⚙ \(.name)\u001b[0m \(.input | (.command // .description // .file_path // .pattern // .prompt // tostring) | tostring | gsub("\n"; " ") | .[0:160])"
      elif .type == "tool_result" then "\u001b[2m  ↳ \(.content | if type == "string" then . else (map(.text? // "") | join(" ")) end | gsub("\n"; " ") | .[0:200])\u001b[0m"
      else empty end
    end'
