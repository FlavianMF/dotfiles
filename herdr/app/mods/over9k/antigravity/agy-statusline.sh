#!/bin/sh
# Antigravity CLI (agy) custom status line (settings.json statusLine, stacked
# under the default one): usage limits per model group. Optional: Options ›
# Session footers › Antigravity (setup.sh agy on). Needs jq. Inside Herdr it saves model,
# effort and context for this terminal in the
# files Over9k keeps (~/.cache/over9k/agents/<HC_TERMINAL_ID>.json), which Over9k's
# Spaces list shows after the agent's name. lastAt (for "3m") moves when the
# output token count does.
in=$(cat)
# Its title: agy's own, else its summary's (agy often sends null), as agy-title.sh.
title=$(printf '%s' "$in" | sh "$(dirname "$0")/agy-title.sh")
[ "$title" = Antigravity ] && title=""
# The line itself (under agy's own, which already shows the model and effort),
# in the same order as Over9k's Claude Code line after those: context, then the
# 5-hour and weekly limits of the group
# the current model draws on (agy's quota buckets: gemini-*, and 3p-* for Claude
# and GPT), then the other group's, named. Each used % coloured (green, yellow
# from 50%, red from 80%), the time to reset dimmed; sections 3 spaces apart.
printf '%s' "$in" | jq -r '
  def left: (. // 0) as $s | if $s <= 0 then "now"
    elif $s < 3600 then "\($s / 60 | floor)m"
    elif $s < 86400 then "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m"
    else "\($s / 86400 | floor)d \($s % 86400 / 3600 | floor)h" end;
  def color: (if . >= 80 then "31" elif . >= 50 then "33" else "32" end) as $c | "\u001b[\($c)m\(round)%\u001b[0m";
  def dim: "\u001b[2m\(.)\u001b[0m";
  def bucket($q; $k; $label): $q[$k] // empty
    | "\($label) \((1 - (.remaining_fraction // 1)) * 100 | color) " + ("· \(.reset_in_seconds | left)" | dim);
  def limits($q; $p): [bucket($q; "\($p)-5h"; "5h"), bucket($q; "\($p)-weekly"; "week")];
  (.quota // {}) as $q
  | (.model.display_name // "") as $dn
  | ($dn | test("^Gemini"; "i")) as $gem
  | (if $gem then ["gemini", "3p", "Claude/GPT"] else ["3p", "gemini", "Gemini"] end) as [$mine, $other, $otherName]
  | [ (.context_window.used_percentage // empty | "context \(color)"),
      limits($q; $mine)[],
      (limits($q; $other) | select(length > 0) | "\($otherName) " + join("   ")) ]
  | join("   ")' 2>/dev/null
# The limits and plan for the sidebar's usage section (over9k-usage).
u="$HOME/.cache/over9k/usage"; mkdir -p "$u"
# Every running agy writes here, some with numbers it saw a while ago, so each limit keeps the newest
# seen: the later reset, and for the same reset the most used.
saved=$(jq -c . "$u/antigravity.json" 2>/dev/null); [ -n "$saved" ] || saved={}
printf '%s' "$in" | jq -ce --argjson saved "$saved" '
  def newest($old):
    if $old == null or (.reset_time // "") > ($old.reset_time // "") then .
    elif (.reset_time // "") < ($old.reset_time // "") then $old
    elif ($old.remaining_fraction // 1) < (.remaining_fraction // 1) then .remaining_fraction = $old.remaining_fraction
    else . end;
  select(.quota != null)
  | {at: (now | floor), plan: .plan_tier,
     quota: (.quota | with_entries(.key as $k | .value |= newest($saved.quota[$k])))}' \
  > "$u/antigravity.json.tmp" 2>/dev/null && mv "$u/antigravity.json.tmp" "$u/antigravity.json" || rm -f "$u/antigravity.json.tmp"
[ -n "$HC_TERMINAL_ID" ] || exit 0
dir="$HOME/.cache/over9k/agents"; mkdir -p "$dir"
f="$dir/$HC_TERMINAL_ID.json"
prev=$(cat "$f" 2>/dev/null); [ -n "$prev" ] || prev={}
printf '%s' "$in" | jq -c --argjson prev "$prev" --arg title "$title" '
  (.context_window.total_output_tokens // 0) as $out
  | {model: (.model.display_name // .model.id // "" | sub(" *\\((Low|Medium|High|Xhigh|Max|Minimal)\\)$"; "")),
     id: .model.id, effort: (.model.effort // null), agent: "antigravity",
     context: .context_window.used_percentage, out: $out,
     lastAt: (if $prev.lastAt != null and ($prev.out // 0) == $out then $prev.lastAt
              elif $out > 0 then (now | floor) else null end),
     conversation: (if (.conversation_id // "") != "" then .conversation_id else $prev.conversation // null end),
     title: (if $title != "" then $title else $prev.title // null end)}' > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" || rm -f "$f.tmp"
