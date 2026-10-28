# Helpers de LLM local: Lenovo LOQ 15IRX11 (83UX) + RTX 5050 Laptop (sm_120a) no WSL2.
_nvsmi=/usr/lib/wsl/lib/nvidia-smi
_boost_ps1="$HOME/dotfiles/powershell/Set-LenovoLlmBoost.ps1"

gpu-stat() {
  "$_nvsmi" --query-gpu=pstate,clocks.mem,clocks.sm,power.draw,memory.used,utilization.gpu --format=csv "$@"
}
gpu-watch() { gpu-stat -l "${1:-1}"; }

llm-boost() {
  local win; win="$(wslpath -w "$_boost_ps1")" || return 1
  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win"
  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win" -Status
  gpu-stat
}

llama-build-sm120a() { "$HOME/dotfiles/bin/llama-build-sm120a" "$@"; }

# llama-moe <modelo.gguf> [n-cpu-moe=99] [args do llama-server...]
llama-moe() {
  local model="$1" n="${2:-99}"; shift $(( $# >= 2 ? 2 : $# ))
  llama-server -m "$model" -ngl 99 --n-cpu-moe "$n" --threads 6 -fa on --jinja "$@"
}

# llama-bench-rtx5050 <modelo.gguf> [args do llama-bench...]
llama-bench-rtx5050() {
  local model="$1"; shift
  llama-bench -m "$model" -p 512 -n 128 -ngl 99 -r 5 "$@"
}

# Backend local único: llama-server no WSL2 (porta 8080). Veja bin/llm-serve.
llm-serve() { "$HOME/dotfiles/bin/llm-serve" "$@"; }
llm-health() { curl -fsS -m 2 "http://127.0.0.1:${LLM_PORT:-8080}/health" && echo; }
llm-stop() { pkill -x llama-server && echo "llama-server parado" || echo "llama-server não estava rodando"; }
