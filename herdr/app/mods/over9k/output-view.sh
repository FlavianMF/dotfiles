#!/bin/sh
# A background shell's or monitor's output ($1), live, titled with what it is ($2).
printf '\033]0;%s\007' "$2"
exec tail -n +1 -F "$1"
