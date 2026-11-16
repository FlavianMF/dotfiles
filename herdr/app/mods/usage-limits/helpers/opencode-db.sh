#!/bin/sh
mode=$1
db=$2
NO_READING=1
sqlite=${HERDR_USAGE_SQLITE_BIN:-sqlite3}
adapters=$(dirname "$0")/opencode

case "$mode" in
  session)
    cwd=$3
    start=$4
    case "$cwd" in /*) ;; *) exit "$NO_READING" ;; esac
    case "$start" in '' | *[!0-9]*) exit "$NO_READING" ;; esac
    names=ul_
    files=
    ;;
  spend)
    names=ul_spend_
    files=-spend
    ;;
  *) exit "$NO_READING" ;;
esac

command -v "$sqlite" >/dev/null 2>&1 || exit "$NO_READING"
[ -f "$db" ] || exit "$NO_READING"

read_only() { "$sqlite" -readonly -batch -cmd '.timeout 2000' "$db" "$1" </dev/null 2>/dev/null; }

tables=$(read_only "select ',' || group_concat(name, ',') || ',' from sqlite_master where type = 'table';") || exit "$NO_READING"

has_tables() {
  for table; do
    case "$tables" in *,"$table",*) ;; *) return 1 ;; esac
  done
}

views=
sessions=
messages=
add_store() {
  views="$views
$(cat "$adapters/$1$files.sql")" || exit "$NO_READING"
  sessions="${sessions:+$sessions union all }select * from ${names}sessions_$2"
  messages="${messages:+$messages union all }select * from ${names}messages_$2"
}

legacy_store_present() {
  has_tables session message || return 1
  [ "$mode" = spend ] || has_tables part
}

if legacy_store_present; then add_store legacy v1; fi
if has_tables session_v2 session_message; then add_store current v2; fi
[ -n "$sessions" ] || exit "$NO_READING"

spend() {
  query=$(cat "$adapters/spend.sql") || exit "$NO_READING"
  read_only "begin;
  create temp view ul_clock as select
    cast(strftime('%s', 'now') as integer) * 1000 + 999 as now_ms,
    cast(strftime('%s', 'now', 'localtime', 'start of day', 'utc') as integer) * 1000 as today_start,
    cast(strftime('%s', 'now', 'localtime', 'start of day', '-6 days', 'utc') as integer) * 1000 as week_start;
  $views
  create temp view ul_spend_sessions as $sessions;
  create temp view ul_spend_messages as $messages;
  $query
  commit;" || exit "$NO_READING"
}

session() {
  query=$(cat "$adapters/session.sql") || exit "$NO_READING"
  quoted_cwd=$(printf '%s' "$cwd" | sed "s/'/''/g")
  row=$(read_only "begin;
  create temp view ul_target as select '$quoted_cwd' as directory, ${start}000 as since;
  $views
  create temp view ul_sessions as $sessions;
  create temp view ul_messages as $messages;
  $query
  commit;") || exit "$NO_READING"
  IFS='|' read -r tokens calls compactions model <<ROW
$row
ROW
  case "$tokens" in '' | *[!0-9]* | 0) exit "$NO_READING" ;; esac
  case "$calls" in '' | *[!0-9]*) exit "$NO_READING" ;; esac
  case "$compactions" in '' | *[!0-9]*) exit "$NO_READING" ;; esac
  case "$model" in '' | *[!A-Za-z0-9._:/-]*) model= ;; esac
  printf 'tokens=%s calls=%s compactions=%s' "$tokens" "$calls" "$compactions"
  [ -z "$model" ] || printf ' model=%s' "$model"
  printf '\n'
}

"$mode"
