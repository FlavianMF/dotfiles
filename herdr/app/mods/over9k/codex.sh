#!/bin/sh
# What a Codex agent (in Herdr terminal $1) has going, one line each,
# tab-separated like tasks.sh: kind, id, what it is, when it started (seconds),
# a detail.
#   csub    a subagent of its own (spawn_agent) still on its task: id is its
#           session's, "Nickname: task", its role. Its session file names the
#           parent's (parent_thread_id); it's done once that file's last task
#           event is a completion or an abort.
#   cshell  a command Codex runs that is still going (a background terminal, or
#           a long one in front), a few seconds old: its process id, the
#           command. Commands run under Codex's sandbox: a child of its
#           codex-linux-sandbox (the bwrap that sets the sandbox up aside).
# Codex's files are found through the files its processes hold open (Linux /proc).
[ -d /proc ] || exit 0
pid=$(hc get "$1" --json 2>/dev/null | jq -r '.pid // empty')
[ -n "$pid" ] || exit 0
now=$(date +%s)
ps=$(ps -eo pid=,ppid=,etimes=,args= | awk '{ args = $0; sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ +/, "", args); gsub(/\t/, " ", args); print $1 "\t" $2 "\t" $3 "\t" args }')
# Its processes: the terminal's program and everything under it.
mine=$(printf '%s\n' "$ps" | awk -F '\t' -v root="$pid" '{ parent[$1] = $2; line[$1] = $0 } END {
  for (p in parent) { q = p; while (q && q != root && q in parent) q = parent[q]; if (q == root) print line[p] } }')
printf '%s\n' "$mine" | awk -F '\t' -v now="$now" '
  { row[NR] = $0; if ($4 ~ /(^|\/)codex-linux-sandbox .*--command-cwd/) inner[$1] = 1 }
  END { for (i = 1; i <= NR; i++) { split(row[i], f, "\t")
    if ((f[2] in inner) && f[3] >= 5 && f[4] !~ /^[^ ]*bwrap /) printf "cshell\t%s\t%s\t%d\t\n", f[1], f[4], now - f[3] } }'
# Its session files, held open.
files=$(for p in $(printf '%s\n' "$mine" | cut -f 1); do ls -l "/proc/$p/fd" 2>/dev/null; done | grep -o '/[^ ]*/rollout-[^ ]*\.jsonl' | sort -u)
for f in $files; do
  head -n 5 "$f" | jq -c 'select(.type == "session_meta") | .payload' 2>/dev/null | head -n 1 | jq -r --arg f "$f" '
    ((.source | objects | .subagent.thread_spawn) // null) as $s
    | select($s != null)
    | [.id, ($s.agent_nickname // "-"), ($s.agent_path // "-" | sub("^/root/"; "")), ($s.agent_role // "subagent"),
       (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdate), $f] | map(tostring) | join("|")'
done | while IFS="|" read -r id nick task role start f; do
  last=$(grep -o '"type":"\(task_started\|task_complete\|turn_aborted\)"' "$f" | tail -n 1)
  case "$last" in *task_complete*|*turn_aborted*) continue ;; esac
  [ "$nick" = - ] && nick=""
  name="${nick:+$nick: }$(printf '%s' "$task" | tr '_' ' ')"
  printf 'csub\t%s\t%s\t%s\t%s\n' "$id" "$name" "$start" "$role"
done
