#!/usr/bin/env bash
# lib/pc-ctl-log.sh - Módulo de registro de decisões de energia do pc-ctl
# Registra cada decisão em formato JSON Lines em ~/.local/state/pc-ctl/sleep.log

pc_ctl_log() {
    local cmd=""
    local result=""
    local reason=""
    local profile=""
    local until=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cmd)
                cmd="${2:-}"
                shift 2
                ;;
            --result)
                result="${2:-}"
                shift 2
                ;;
            --reason)
                reason="${2:-}"
                shift 2
                ;;
            --profile)
                profile="${2:-}"
                shift 2
                ;;
            --until)
                until="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        echo "Erro pc_ctl_log: --cmd é obrigatório" >&2
        return 1
    fi

    case "$result" in
        applied|refused|failed|dry-run)
            ;;
        *)
            echo "Erro pc_ctl_log: result deve ser 'applied', 'refused', 'failed' ou 'dry-run' (recebido: '$result')" >&2
            return 1
            ;;
    esac

    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local log_file="${PC_CTL_LOG_FILE:-$HOME/.local/state/pc-ctl/sleep.log}"
    local log_dir
    log_dir="$(dirname "$log_file")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi

    python3 -c '
import json, sys
ts, cmd, result, reason, profile, until = sys.argv[1:7]
entry = {
    "ts": ts,
    "cmd": cmd,
    "result": result,
    "reason": reason if reason else None,
    "profile": profile if profile else None,
    "until": until if until else None,
}
print(json.dumps(entry, separators=(",", ":")))
' "$ts" "$cmd" "$result" "$reason" "$profile" "$until" >> "$log_file"
}
