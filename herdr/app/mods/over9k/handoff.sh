#!/bin/sh
# Over9k's hand-off: moves work from a chat to a space of its own, in Herdr.
# Over9k installs it (with resume.sh) in ~/.local/share/over9k on every computer.
#   handoff.sh --to <name or folder> [--brief <text>] [--from <terminal>]
#     A name is a new space in the projects path; a path (/… or ~/…) is that
#     folder, new or not. Its space is shown (made if it isn't open) and the same
#     kind of agent starts there, on the same model, with the brief as its first
#     message. --from is the agent handing off (default: the one running this).
#   handoff.sh --list    the spaces it can hand off to
#   handoff.sh --rule on|off   add or remove the hand-off rule in each agent's
#                        global instructions (CLAUDE.md, AGENTS.md)
# Chats, Projects and this computer's spaces come from Over9k, which writes them
# to locations.json and spaces.json next to this script.
DATA="$HOME/.local/share/over9k"
tilde() { case "$1" in "$HOME") echo "~";; "$HOME"/*) echo "~${1#"$HOME"}";; *) echo "$1";; esac; }
full() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#"~/"}" ;; *) echo "$1" ;; esac; }
projects=$(full "$(jq -r '.projects // empty' "$DATA/locations.json" 2>/dev/null)"); [ -n "$projects" ] || projects="$HOME/Code"
chats=$(full "$(jq -r '.chats // empty' "$DATA/locations.json" 2>/dev/null)"); [ -n "$chats" ] || chats="$HOME"

# The rule, between markers so it can be taken out again exactly.
rule() {
  cat <<EOF
<!-- over9k:handoff -->
## Hand off project work (Over9k)

When you're not in a project (outside the user's projects path, $(tilde "$projects"),
and their listed spaces; chats start in $(tilde "$chats")) and the task turns
into project work (writing or editing a project's files, building, testing,
git), don't do it there. Hand it off:

    sh ~/.local/share/over9k/handoff.sh --to <name or folder> --brief "<brief>"

\`--to\` a short name makes a new space in the projects path; a folder hands off to
that one (\`--list\` shows the existing spaces). The brief is self-contained: the
user's request in their words, what you found, constraints. It opens that space
in Herdr with a new agent that starts on your brief. Then tell the user in one
line where it went, and stop. Quick questions, research and anything about the
machine itself stay here.
<!-- /over9k:handoff -->
EOF
}

case "${1:-}" in
  --list)
    { jq -r 'keys[]' "$DATA/spaces.json" 2>/dev/null
      for d in "$projects"/*/; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done; } | awk '!seen[$0]++' | while read -r d; do tilde "$d"; done
    exit 0 ;;
  --rule)
    # Every agent's file, installed or not yet: the rule is there when it is.
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"; do
      [ "${2:-}" = on ] && mkdir -p "$(dirname "$f")"
      [ -d "$(dirname "$f")" ] || continue
      if [ -f "$f" ]; then
        # Out with the block and the blank lines it leaves at the end.
        tmp="$f.over9k.$$"
        sed '/<!-- over9k:handoff -->/,/<!-- \/over9k:handoff -->/d' "$f" | awk 'NF { for (; n > 0; n--) print ""; print; next } { n++ }' > "$tmp" && mv "$tmp" "$f"
      fi
      if [ "${2:-}" = on ]; then
        { [ -s "$f" ] && printf '\n'; rule; } >> "$f"
      elif [ -f "$f" ] && [ ! -s "$f" ]; then
        rm -f "$f" # only ever held the rule
      fi
    done
    exit 0 ;;
esac

to="" brief="" from="${HC_TERMINAL_ID:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --to) to=$2; shift 2 ;;
    --brief) brief=$2; shift 2 ;;
    --from) from=$2; shift 2 ;;
    *) echo "usage: handoff.sh --to <name or folder> [--brief <text>] | --list | --rule on|off" >&2; exit 2 ;;
  esac
done
[ -n "$to" ] || { echo "usage: handoff.sh --to <name or folder> [--brief <text>]" >&2; exit 2; }
case "$to" in
  "~"|"~/"*) dir=$(full "$to") ;;
  /*) dir=$to ;;
  *) dir="$projects/$to" ;;
esac
dir=${dir%/}
mkdir -p "$dir" || exit 1

# The agent handing off: its program, and its model when that's not its usual one
# (Claude Code's status line file says; Pi's footer does).
app=$(hc ls --json 2>/dev/null | jq -r --arg t "$from" '[.terminals[]? | select(.address == $t)][0].agent // empty')
model=""
case "$app" in
  codex) agent=codex ;;
  pi) agent=pi
      model=$(hc read "$from" --lines 8 2>/dev/null | grep -oE '[^ ]+ • [^ ]+[[:space:]]*$' | tail -n 1 | cut -d ' ' -f 1) ;;
  *) agent=claude
     id=$(jq -r '.id // empty' "$HOME/.cache/over9k/agents/$from.json" 2>/dev/null)
     case "$id" in claude-*|"") ;; *) model=$id ;; esac ;;
esac
[ -n "$brief" ] || brief="This was handed off from a chat. Ask me what we're working on."
case "$agent" in codex) name=Codex ;; pi) name=Pi ;; *) name="Claude Code" ;; esac

if command -v herdr-app >/dev/null 2>&1 && herdr-app status >/dev/null 2>&1; then
  # Herdr runs here: its space on that folder, else a new one.
  space=$(herdr-app ls | jq -r --arg d "$dir" '[.spaces[] | select(.machine == null and ((.folder // "") | rtrimstr("/")) == $d)][0].id // empty')
  argv=$(jq -nc --arg r "$DATA/resume.sh" --arg a "$agent" --arg m "$model" '["sh", $r, $a, "", $m, ""]')
  if [ -n "$space" ]; then
    herdr-app do space.select "$(jq -nc --arg s "$space" '{id: $s}')" >/dev/null
    out=$(herdr-app do tab.new "$(jq -nc --arg s "$space" --arg d "$dir" --arg n "$name" --argjson v "$argv" --arg b "$brief" '{space: $s, folder: $d, name: $n, argv: $v, task: $b}')")
  else
    out=$(herdr-app do space.new "$(jq -nc --arg d "$dir" --arg n "$name" --argjson v "$argv" --arg b "$brief" '{name: ($d | split("/") | last), folder: $d, tab: $n, argv: $v, task: $b}')")
  fi
  printf '%s' "$out" | jq -e '.terminal' >/dev/null 2>&1 || { echo "Couldn't hand off to $(tilde "$dir"): $out" >&2; exit 1; }
else
  # Another computer's Herdr window shows this one's core: a terminal labelled
  # with a space and a tab shows up there (an id it doesn't know makes a new one).
  space=$(jq -r --arg d "$dir" '.[$d] // empty' "$DATA/spaces.json" 2>/dev/null)
  stamp=$(date +%s)$$
  [ -n "$space" ] || space="over9k-$stamp"
  hc run --bg --keep --label "herdr.space=$space" --label "herdr.tab=over9k-tab-$stamp" --cwd "$dir" \
    -- sh "$DATA/resume.sh" "$agent" "" "$model" "" "$brief" >/dev/null || { echo "Couldn't hand off to $(tilde "$dir")" >&2; exit 1; }
fi
# Pinned in the sidebar (Over9k picks the folder up from here), so it stays listed.
printf '%s\n' "$dir" >> "$DATA/pin"
echo "Handed off to $(tilde "$dir"): a new $name agent there has the brief."
