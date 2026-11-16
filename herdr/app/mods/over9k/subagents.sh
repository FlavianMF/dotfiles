#!/bin/sh
# Claude Code's subagents for a transcript ($1), from <transcript>/subagents/:
# one line each, tab-separated: id, last write (seconds), description, type,
# model, when it started (seconds), its context (the last request's input
# tokens), effort, context window, and 1 once it's done.
# Done: the parent was told so (a "finished", killed or failed notice for its
# task id; one waiting on work of its own isn't, though it writes nothing
# meanwhile), it was stopped (TaskStop: its notice only comes at the parent's
# next turn), it handed its report back (a message from it), or it never
# replied (two minutes on: a leftover, not one that runs). A signal only counts
# if the subagent has written nothing since: one told to carry on (SendMessage)
# runs again, with the old "finished" still in the parent's transcript. The parent's
# transcript (big) is read once for all of them; the answer is kept until it or
# a subagent's file changes, or for a minute at most.
# The parent's transcript only grows, and can reach hundreds of MB: its done
# signals are kept (a .state file, with the bytes read so far), and each run
# reads only what was added since; one that got shorter or starts differently
# was written anew, and is read from the top. What a subagent's own file says
# is kept too (a .seen file), until that file changes.
dir="${1%.jsonl}/subagents"; [ -d "$dir" ] || exit 0
now=$(date +%s)
cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/over9k"; mkdir -p "$cachedir"
cache="$cachedir/subagents-$(printf '%s' "$1" | cksum | cut -d ' ' -f 1)"
stamp() { stat -c '%Y %s' "$1" 2>/dev/null || stat -f '%m %z' "$1" 2>/dev/null; }
# Bump v when this script changes, so cached answers (and states) from the old one go.
v=5
newest=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -n 1)
key="v$v $(stamp "$1") $(stamp "$newest") $((now / 60))"
if [ -f "$cache" ] && [ "$(head -n 1 "$cache")" = "$key" ]; then tail -n +2 "$cache"; exit 0; fi

# Each done signal in the parent's transcript, as "id seconds": from the bytes
# added since the state's offset, whole lines only (one being written waits for
# the next run), after those found before. They're read in slices of 16 MB at
# most, the state saved after each: a run cut short keeps what it read, and the
# next one goes on from there. Its working files go when it ends, even cut
# short; ones left by a run killed outright go a few minutes on.
# macOS's tail and grep go at tens of MB a second, perl at GB: where there's
# one, it reads a slice (piece file offset bytes) and skips the state's first
# line (rest file). And unless grep is GNU's or ugrep (faster still), it keeps
# only the lines a pattern (an ERE that means the same in perl) could match
# (lines pattern file), for the greps after it to look in.
if command -v perl > /dev/null 2>&1; then
  piece() { perl -e 'open F, "<", $ARGV[0] or exit 1; seek F, $ARGV[1], 0; read F, $b, $ARGV[2]; print $b' "$@"; }
  rest() { perl -ne 'print if $. > 1' "$1"; }
  lines() { P="$1" perl -ne 'BEGIN { $p = qr/$ENV{P}/ } print if /$p/' "$2"; }
  # A subagent's file in one go (facts file reply): its last model, its last
  # effort and 1 if it asked for a 1M context, a line each, and its last reply
  # into the file named.
  facts() { A="$2" perl -ne '$m = $1 while /"model":"([^"<|]*)"/g; $e = $1 while /"effort":"([a-z]*)"/g;
    $c = 1 if /context-1m/; $a = $_ if /"type":"assistant"/;
    END { print "$m\n$e\n", ($c ? 1 : 0), "\n"; open A, ">", $ENV{A}; print A $a }' "$1"; }
else
  piece() { tail -c +$(($2 + 1)) "$1" | head -c "$3"; }
  rest() { tail -n +2 "$1"; }
fi
case "$(grep --version 2>/dev/null | head -n 1)" in
  *'(GNU grep)'*|ugrep*) unset -f lines facts ;;
esac
command -v lines > /dev/null 2>&1 || lines() { LC_ALL=C grep -E "$1" "$2"; }
command -v facts > /dev/null 2>&1 || facts() {
  printf '%s\n' "$(grep -o '"model":"[^"<|]*"' "$1" 2>/dev/null | tail -n 1 | cut -d '"' -f 4)" \
    "$(grep -o '"effort":"[a-z]*"' "$1" 2>/dev/null | tail -n 1 | cut -d '"' -f 4)"
  if grep -q 'context-1m' "$1" 2>/dev/null; then echo 1; else echo 0; fi
  grep '"type":"assistant"' "$1" 2>/dev/null | tail -n 1 > "$2"; }
state="$cache.state" chunk="$cache.$$.chunk" locked= partial=
trap '[ -n "$locked" ] && rmdir "$lock" 2>/dev/null; rm -f "$chunk" "$chunk.w" "$cache.$$" "$chunk.f" "$cache.$$.all" "$state.$$" "$cache.seen.$$" "$cache.$$.reply" "$cache.$$".list "$cache.$$".stat "$cache.$$".meta "$cache.$$".fin "$cache.$$".sig "$cache.$$".new "$cache.$$".rows' EXIT
trap 'exit 1' HUP INT TERM
find "$cachedir" -maxdepth 1 \( -name '*.chunk*' -o -name '*.old' -o -name '*.state.[0-9]*' \) -mmin +5 -exec rm -f {} + 2>/dev/null
if [ -f "$1" ]; then
  start=$(head -c 4096 "$1" | cksum | cut -d ' ' -f 1)
  sv= off=0 was=
  [ -f "$state" ] && read -r sv off was < "$state"
  case "$off" in ''|*[!0-9]*) off=0 sv= ;; esac
  size=$(wc -c < "$1" | tr -d ' ')
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
    # 15 s at most, well inside exec's 30 s and leaving time for the subagents'
    # own files: what's left waits for the next run, and the answer from what
    # was read isn't kept.
    [ $(($(date +%s) - now)) -lt 15 ] || { partial=1; break; }
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
    { echo "v$v $((off + n)) $start"
      rest "$state"
      lines '<task-id>|Successfully stopped task: |agent-message from=' "$chunk" 2>/dev/null | jq -Rr '
      (try (fromjson | .timestamp // empty | sub("\\.[0-9]+Z$"; "Z") | fromdate) catch empty) as $t
      | ( (scan("<task-id>[a-z0-9]*</task-id>.{0,600}") | select(test("finished</summary>|<status>(killed|failed|stopped)</status>")) | capture("^<task-id>(?<i>[a-z0-9]*)").i),
          (scan("Successfully stopped task: [a-z0-9]*") | split(" ")[3]),
          (scan("agent-message from=\\\\\"[a-z0-9]*") | sub(".*\""; "")) )
      | "\(.) \($t)"' 2>/dev/null
    } > "$state.$$" && mv -f "$state.$$" "$state" || break
    off=$((off + n))
  done
  rm -f "$chunk" "$chunk.f"
  signals=$(rest "$state" | sort -k1,1 -k2,2n)
fi

# What each subagent's file says, kept with its stamp (a .seen file, a line
# each, |-separated: id, stamp, model, start, tokens, effort, window, last
# record, and 1 if it ever replied), so only ones that wrote since are read again.
# What every one needs is asked once for all of them (a process costs a few ms,
# more on macOS, and there can be hundreds): the files' stamps, the meta files'
# descriptions and types, which are marked finished; then joined in one awk.
seen="$cache.seen"; [ -f "$seen" ] || : > "$seen"
w="$cache.$$"; : > "$w.list"
for m in "$dir"/*.meta.json; do
  [ -f "$m" ] && [ -f "${m%.meta.json}.jsonl" ] && printf '%s\n' "${m%.meta.json}" >> "$w.list"
done
# (None: nothing to ask, and xargs would run them with none, reading stdin.)
: > "$w.stat"; : > "$w.meta"; : > "$w.fin"
if [ -s "$w.list" ]; then
  if stat -c %Y / > /dev/null 2>&1; then sfmt='-c %n|%Y|%s'; else sfmt='-f %N|%m|%z'; fi
  sed 's/$/.jsonl/' "$w.list" | tr '\n' '\0' | xargs -0 stat $sfmt > "$w.stat" 2>/dev/null
  sed 's/$/.meta.json/' "$w.list" | tr '\n' '\0' | xargs -0 jq -r '[input_filename, .description // "", .agentType // ""] | @tsv' > "$w.meta" 2>/dev/null ||
    while read -r b; do jq -r '[input_filename, .description // "", .agentType // ""] | @tsv' "$b.meta.json" 2>/dev/null; done < "$w.list" > "$w.meta"
  # Newer Claude Codes mark it done in its meta file too (and unmark it on a resume).
  sed 's/$/.meta.json/' "$w.list" | tr '\n' '\0' | xargs -0 grep -l '"finished":true' > "$w.fin" 2>/dev/null
fi
printf '%s\n' "$signals" > "$w.sig"
# The ones not seen as they are now: read, and their rows put in the .seen file.
awk -v v="$v" -v S="$w.stat" '
  FILENAME == S { n = split($0, a, "|"); b = a[1]; sub(/\.jsonl$/, "", b); st[b] = "v" v "-" a[n - 1] "_" a[n]; next }
  { split($0, a, "|"); have[a[1] "|" a[2]] = 1 }
  END { for (b in st) { id = b; sub(/.*\//, "", id); if (!have[id "|" st[b]]) print b "|" st[b] } }' "$w.stat" "$seen" > "$w.new"
if [ -s "$w.new" ]; then
  while IFS='|' read -r b st; do
    j="$b.jsonl"; id="${b##*/}"
    # Its model, its effort (each reply records it) and context window: 1M when
    # its requests asked for that (the context-1m beta), else 200k.
    { read -r model; read -r effort; read -r big; } <<EOF
$(facts "$j" "$cache.$$.reply")
EOF
    window=200000; [ "$big" = 1 ] && window=1000000
    start=$(head -n 1 "$j" | jq -r '.timestamp // empty | sub("\\.[0-9]+Z$"; "Z") | fromdate' 2>/dev/null)
    tokens=$(jq -r '.message.usage | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))' "$cache.$$.reply" 2>/dev/null)
    # Its last record, not its file's time: a session started again rewrites those.
    last=$(tail -n 20 "$j" | jq -r '.timestamp // empty | sub("\\.[0-9]+Z$"; "Z") | fromdate' 2>/dev/null | tail -n 1)
    replied=0; [ -s "$cache.$$.reply" ] && replied=1
    echo "$id|$st|$model|$start|$tokens|$effort|$window|$last|$replied"
  done < "$w.new" > "$w.rows"
  awk -v R="$w.rows" 'FILENAME == R { split($0, a, "|"); drop[a[1]] = 1; rows[++n] = $0; next }
    { split($0, a, "|"); if (!drop[a[1]]) print } END { for (i = 1; i <= n; i++) print rows[i] }' "$w.rows" "$seen" > "$seen.$$" && mv -f "$seen.$$" "$seen"
fi
# Done: a signal it wrote nothing after, marked finished, or it never replied
# two minutes on (not one that runs: a session started again can write back an
# old one's files with nothing in them).
awk -v now="$now" -v v="$v" -v S="$w.stat" -v M="$w.meta" -v F="$w.fin" -v E="$seen" -v G="$w.sig" '
  FILENAME == S { n = split($0, a, "|"); b = a[1]; sub(/\.jsonl$/, "", b); at[b] = a[n - 1]; st[b] = "v" v "-" a[n - 1] "_" a[n]; next }
  FILENAME == M { b = $0; sub(/\t.*/, "", b); sub(/\.meta\.json$/, "", b); dt[b] = substr($0, index($0, "\t") + 1); next }
  FILENAME == F { b = $0; sub(/\.meta\.json$/, "", b); fin[b] = 1; next }
  FILENAME == E { split($0, a, "|"); row[a[1] "|" a[2]] = $0; next }
  FILENAME == G { split($0, a, " "); if (a[2] != "") said[a[1]] = a[2]; next }
  { b = $0; id = b; sub(/.*\//, "", id); sid = id; sub(/^agent-/, "", sid)
    split(row[id "|" st[b]], x, "|"); last = x[8]; if (last == "") last = 0
    d = 0; if (sid in said && last + 0 <= said[sid] + 5) d = 1
    if (fin[b]) d = 1
    t = (b in at) ? at[b] : 0
    if (!d && now - t > 120 && x[9] == "0") d = 1
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, t, dt[b], x[3], x[4], x[5], x[6], x[7], d }' "$w.stat" "$w.meta" "$w.fin" "$seen" "$w.sig" "$w.list" > "$cache.$$"
rm -f "$w.list" "$w.stat" "$w.meta" "$w.fin" "$w.sig" "$w.new" "$w.rows"
# Its own file, put in place whole: two runs at once (a slow one outlasting the
# sidebar's wait) wrote over each other's, losing rows.
# One answered while another run reads isn't kept: the next run asks again.
if [ -n "$partial" ]; then cat "$cache.$$"; rm -f "$cache.$$"; exit 0; fi
{ echo "$key"; cat "$cache.$$"; } > "$cache.$$.all" && mv -f "$cache.$$.all" "$cache"; rm -f "$cache.$$"
tail -n +2 "$cache"
