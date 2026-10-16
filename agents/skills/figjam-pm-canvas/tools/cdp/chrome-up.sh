#!/usr/bin/env bash
# Sobe Xvfb :99 + x11vnc (localhost:5900) + Chrome com CDP 9222, desacoplados da sessão.
pkill -f figjam-pm-canvas-chrome; sleep 2
pgrep -x Xvfb >/dev/null || { setsid nohup Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 </dev/null & disown; sleep 2; }
pgrep -x x11vnc >/dev/null || { setsid nohup x11vnc -display :99 -localhost -nopw -forever -shared -rfbport 5900 >/dev/null 2>&1 </dev/null & disown; }
DISPLAY=:99 setsid nohup google-chrome --remote-debugging-port=9222 \
  --user-data-dir="$HOME/.cache/figjam-pm-canvas-chrome" --no-first-run --ignore-gpu-blocklist \
  --use-angle=swiftshader --enable-unsafe-swiftshader --window-size=1920,1080 --start-maximized \
  "$@" >/dev/null 2>&1 </dev/null & disown
for i in $(seq 1 20); do curl -s localhost:9222/json/version >/dev/null && break; sleep 1; done
pgrep -a Xvfb | head -1; pgrep -a x11vnc | head -1; curl -s localhost:9222/json/version | grep Browser
