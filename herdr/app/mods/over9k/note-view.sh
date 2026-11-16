#!/bin/sh
# A scheduled prompt or wakeup, shown in place (over9k's sub-rows): its title
# ($1) as the terminal's title and on top, then each line given ($2…), then it
# waits there until closed.
printf '\033]0;%s\007' "$1"
printf '\033[1m%s\033[0m\n\n' "$1"
shift
for line in "$@"; do printf '%s\n' "$line"; done
exec sleep 2147483647
