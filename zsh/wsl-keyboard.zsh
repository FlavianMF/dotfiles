# Layout ABNT2 para apps X11 (XWayland) no WSLg. Apps Wayland seguem o layout do Windows.
if [[ -n "$DISPLAY" ]] && (( $+commands[setxkbmap] )); then
  setxkbmap -model abnt2 -layout br 2>/dev/null
fi
