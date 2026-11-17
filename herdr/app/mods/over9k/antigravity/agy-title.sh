#!/bin/sh
# Antigravity CLI (agy) window title (settings.json "title"): the conversation's
# title, so Herdr (and its mods) name the agent by it; "Antigravity" until it has
# one. agy often sends conversation_title null even once it has made one up, so
# the title is looked up in its summaries by conversation_id then (needs
# sqlite3; without it, the title only). Optional: see README (Antigravity).
in=$(cat)
t=$(printf '%s' "$in" | jq -r '.conversation_title // empty' 2>/dev/null)
if [ -z "$t" ]; then
  id=$(printf '%s' "$in" | jq -r '.conversation_id // empty' 2>/dev/null | tr -cd '0-9a-f-')
  [ -n "$id" ] && t=$(sqlite3 "file:$HOME/.gemini/antigravity-cli/conversation_summaries.db?mode=ro" \
    "select title from conversation_summaries where conversation_id = '$id'" 2>/dev/null | head -n 1)
fi
printf '%s\n' "${t:-Antigravity}"
