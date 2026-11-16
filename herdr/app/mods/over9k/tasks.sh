#!/bin/sh
# What a Claude Code session ($1, its transcript) has running in the background,
# one line each, tab-separated: kind (shell, monitor, cron, wakeup), task id, what it is
# (description, or a cron job's prompt), when it started (seconds), a cron
# job's schedule ("Every 2 hours at :13") or a wakeup's time (seconds), and a
# shell's or monitor's output file. A wakeup (ScheduleWakeup, /loop pacing itself)
# is its latest one, until its time comes or it's stopped. Ended ones are left out: a task with a
# notice carrying a <status>, stopped (TaskStop), or a monitor expired (its
# notice, or past its time limit); a cron job deleted, a
# one-off past its time, or a recurring one past its 7 days.
# The answer is kept until the transcript changes, or for a minute at most.
# A transcript only grows, and can reach hundreds of MB: what it says is kept
# (a .state file: the bytes read so far, and in short what they held), and each
# run reads only what was added since. One that got shorter or starts
# differently was written anew, and is read from the top.
[ -f "$1" ] || exit 0
now=$(date +%s)
dir="${XDG_CACHE_HOME:-$HOME/.cache}/over9k"; mkdir -p "$dir"
cache="$dir/tasks-$(printf '%s' "$1" | cksum | cut -d ' ' -f 1)"
# Bump v when this script changes, so cached answers (and states) from the old one go.
v=7
key="v$v $(stat -c '%Y %s' "$1" 2>/dev/null || stat -f '%m %z' "$1") $((now / 60))"
if [ -f "$cache" ] && [ "$(head -n 1 "$cache")" = "$key" ]; then tail -n +2 "$cache"; exit 0; fi

# Its working files go when it ends, even cut short; ones left by a run killed
# outright (a slice of a transcript, up to 16 MB, and a copy of the state) go a few minutes on.
# macOS's tail and grep go at tens of MB a second, perl at GB: where there's
# one, it reads a slice (piece file offset bytes) and skips the state's first
# line (rest file). And unless grep is GNU's or ugrep (faster still), it keeps
# only the lines a pattern (an ERE that means the same in perl) could match
# (lines pattern file), for the greps after it to look in.
if command -v perl > /dev/null 2>&1; then
  piece() { perl -e 'open F, "<", $ARGV[0] or exit 1; seek F, $ARGV[1], 0; read F, $b, $ARGV[2]; print $b' "$@"; }
  rest() { perl -ne 'print if $. > 1' "$1"; }
  lines() { P="$1" perl -ne 'BEGIN { $p = qr/$ENV{P}/ } print if /$p/' "$2"; }
else
  piece() { tail -c +$(($2 + 1)) "$1" | head -c "$3"; }
  rest() { tail -n +2 "$1"; }
fi
case "$(grep --version 2>/dev/null | head -n 1)" in
  *'(GNU grep)'*|ugrep*) lines() { LC_ALL=C grep -E "$1" "$2"; } ;;
esac
command -v lines > /dev/null 2>&1 || lines() { LC_ALL=C grep -E "$1" "$2"; }
state="$cache.state" chunk="$cache.$$.chunk" locked= partial=
trap '[ -n "$locked" ] && rmdir "$lock" 2>/dev/null; rm -f "$chunk" "$chunk.w" "$cache.$$" "$chunk.f" "$cache.$$.all" "$state.$$"' EXIT
trap 'exit 1' HUP INT TERM
find "$dir" -maxdepth 1 \( -name '*.chunk*' -o -name '*.old' -o -name '*.state.[0-9]*' \) -mmin +5 -exec rm -f {} + 2>/dev/null
# The bytes added since the state's offset, whole lines only (one being written
# waits for the next run), in slices of 16 MB at most, the state saved after
# each: a run cut short keeps what it read, and the next one goes on from there.
start=$(head -c 4096 "$1" | cksum | cut -d ' ' -f 1)
sv= off=0 was=
[ -f "$state" ] && read -r sv off was < "$state"
size=$(wc -c < "$1" | tr -d ' ')
case "$off" in ''|*[!0-9]*) off=0 sv= ;; esac
if [ "$sv" != "v$v" ] || [ "$was" != "$start" ] || [ "$off" -gt "$size" ]; then
  off=0; echo "v$v 0 $start" > "$state.$$" && mv -f "$state.$$" "$state"
fi
slice=16777216
# One run at a time reads it (others answer from the state as it is): runs
# that overlap would read the same slices. A lock left by a run killed
# outright, untouched for two minutes, is taken over.
lock="$cache.lock"
[ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
if mkdir "$lock" 2>/dev/null; then locked=1; else locked= partial=1 size=0; fi
while [ "$off" -lt "$size" ]; do
  # 20 s at most, well inside exec's 30 s: what's left waits for the next
  # run, and the answer from what was read isn't kept.
  [ $(($(date +%s) - now)) -lt 20 ] || { partial=1; break; }
  touch "$lock"
  piece "$1" "$off" "$slice" > "$chunk"
  n=$(wc -c < "$chunk" | tr -d ' ')
  if [ "$n" -gt 0 ] && [ "$(tail -c 1 "$chunk" | od -An -tx1 | tr -d ' \n')" != 0a ]; then
    cut=$((n - $(tail -n 1 "$chunk" | wc -c | tr -d ' ')))
    if [ "$cut" -gt 0 ]; then n=$cut; head -c "$n" "$chunk" > "$chunk.w" && mv -f "$chunk.w" "$chunk"
    # A line still being written waits; one longer than a slice is read in pieces.
    elif [ "$n" -lt "$slice" ]; then break; fi
  fi
  [ "$n" -gt 0 ] || break
  # Only the lines any grep below could match.
  lines '<task-id>|Successfully stopped task: |/tasks/|"name":"(Bash|Monitor|CronCreate|CronDelete|ScheduleWakeup)"|backgroundTaskId|"taskId":"|humanSchedule|scheduledFor' "$chunk" > "$chunk.f" 2>/dev/null
  # What the new lines hold, one fact a line: "E id" a task that ended, "O folder"
  # where its background output goes (a session started again writes to a new
  # one), and as JSON each tool use ({u, n, i}) and tool result ({k, t, r}).
  { echo "v$v $((off + n)) $start"
    rest "$state"
    # Bytes, not characters (LC_ALL=C): the same matches, and some grep (ugrep)
    # takes a second just to set up .{0,600} in a UTF-8 locale.
    { LC_ALL=C grep -o '<task-id>[a-z0-9]*</task-id>.\{0,600\}' "$chunk.f" | LC_ALL=C grep -E '<status>|Monitor expired' | grep -o '^<task-id>[a-z0-9]*' | cut -c10-
      LC_ALL=C grep -o 'Successfully stopped task: [a-z0-9]*' "$chunk.f" | cut -d' ' -f4; } 2>/dev/null | sed 's/^/E /'
    LC_ALL=C grep -o '/[^ "\\<]*/tasks/[a-z0-9]*\.output' "$chunk.f" 2>/dev/null | tail -n 1 | sed 's|/[^/]*$||; s/^/O /'
    LC_ALL=C grep -E '"name":"(Bash|Monitor|CronCreate|CronDelete|ScheduleWakeup)"|backgroundTaskId|"taskId":"|humanSchedule|scheduledFor' "$chunk.f" 2>/dev/null | jq -cR '
      def some: with_entries(select(.value != null));
      fromjson? | if .type == "assistant" then .message.content[]? | select(.type == "tool_use")
          | {u: .id, n: .name, i: (.input | {description, command, prompt, reason, id} | some)}
        elif .type == "user" and (.toolUseResult | type == "object") then
          {k: (.message.content | if type == "array" then .[0].tool_use_id // "" else "" end), t: .timestamp,
           r: (.toolUseResult | {backgroundTaskId, taskId, timeoutMs, scheduledFor, humanSchedule, id, recurring, nextFireAt} | some)}
        else empty end' 2>/dev/null
  } > "$state.$$" && mv -f "$state.$$" "$state" || break
  off=$((off + n))
done
rm -f "$chunk" "$chunk.f"

ended=$(grep '^E ' "$state" | cut -c3- | sort -u | tr '\n' ' ')
outdir=$(grep '^O ' "$state" | tail -n 1 | cut -c3-)
grep '^{' "$state" | jq -rs --arg ended " $ended" --arg out "${outdir:+$outdir/}" --argjson now "$now" '
  [.[] | select(.u)] as $uses
  | ($uses | map({key: .u, value: .}) | from_entries) as $u
  | [$uses[] | select(.n == "CronDelete") | .i.id] as $del
  | ([$uses[] | select(.n == "ScheduleWakeup")] | last | .u // "") as $wake
  | .[] | select(.r) | .r as $r
  | $u[.k] as $use
  | (.t | sub("\\.[0-9]+Z$"; "Z") | fromdate) as $at
  | if $r.backgroundTaskId then ["shell", $r.backgroundTaskId, ($use.i.description // $use.i.command // "Background command"), $at, "", (if $out == "" then "" else $out + $r.backgroundTaskId + ".output" end)]
    elif $r.taskId and $use.n == "Monitor" and ($at + ($r.timeoutMs // 300000) / 1000 > $now) then ["monitor", $r.taskId, ($use.i.description // "Monitor"), $at, "", (if $out == "" then "" else $out + $r.taskId + ".output" end)]
    elif $r.scheduledFor and $use.u == $wake and ($r.scheduledFor / 1000 > $now) then ["wakeup", $use.u, ($use.i.reason // "Wakeup"), $at, ($r.scheduledFor / 1000 | floor), ""]
    elif $r.humanSchedule and ($del | index($r.id) | not)
      and ($r.recurring or ($r.nextFireAt / 1000) > $now - 120)
      and ($now - $at < 7 * 86400) then ["cron", $r.id, ($use.i.prompt // ""), $at, $r.humanSchedule, ""]
    else empty end
  | select(.[0] == "cron" or .[0] == "wakeup" or (.[1] as $id | $ended | contains(" " + $id + " ") | not))
  | map(tostring | gsub("[\t\n]"; " ")) | @tsv' 2>/dev/null > "$cache.$$"
# Its own file, put in place whole: two runs at once wrote over each other's.
# One answered while another run reads isn't kept: the next run asks again.
if [ -n "$partial" ]; then cat "$cache.$$"; rm -f "$cache.$$"; exit 0; fi
{ echo "$key"; cat "$cache.$$"; } > "$cache.$$.all" && mv -f "$cache.$$.all" "$cache"; rm -f "$cache.$$"
tail -n +2 "$cache"
