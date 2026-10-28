# URL do Ollama do Windows vista do WSL. localhost não alcança o Windows; o gateway alcança.
# O opencode lê OLLAMA_BASE_URL via {env:OLLAMA_BASE_URL} em opencode/opencode.json.
# Com networkingMode=mirrored, localhost alcança o Windows: prefira-o ao gateway.
if [[ -z "$OLLAMA_BASE_URL" && -e /proc/sys/fs/binfmt_misc/WSLInterop ]] && (( $+commands[curl] )) \
  && curl -fsS -m 1 -o /dev/null http://localhost:11434/api/version 2>/dev/null; then
  export OLLAMA_BASE_URL="http://localhost:11434/v1"
fi
if [[ -z "$OLLAMA_BASE_URL" && -e /proc/sys/fs/binfmt_misc/WSLInterop ]] && (( $+commands[ip] )); then
  _ollama_gw="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  [[ -n "$_ollama_gw" ]] && export OLLAMA_BASE_URL="http://${_ollama_gw}:11434/v1"
  unset _ollama_gw
fi
# O host do Traycer roda como serviço systemd do usuário e não herda o ambiente do zsh.
# Publique a variável no gerenciador; o host a lê na próxima vez que iniciar.
if [[ -n "$OLLAMA_BASE_URL" ]] && (( $+commands[systemctl] )) \
  && [[ "$(systemctl --user show-environment 2>/dev/null | grep '^OLLAMA_BASE_URL=')" != "OLLAMA_BASE_URL=$OLLAMA_BASE_URL" ]]; then
  systemctl --user set-environment "OLLAMA_BASE_URL=$OLLAMA_BASE_URL" 2>/dev/null
fi
