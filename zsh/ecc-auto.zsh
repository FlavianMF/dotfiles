# ECC automático: antes de abrir o Claude Code, liga o plugin ecc@ecc em projetos web, C e
# backend Node (claude/ecc-project.sh auto). O estado só vale em sessão nova, por isso a ligação
# precisa acontecer antes de a sessão abrir. A função nunca impede o claude de abrir.
#
# Variáveis:
#   ECC_AUTO=0     desliga o wrapper (o claude abre como antes)
#   DOTFILES_DIR   raiz do repo de dotfiles (padrão ~/dotfiles)
# Opt-out por projeto: `make ecc-off DIR=...` ou `touch .claude/ecc.off`. Filtros: claude/ecc-auto.conf.
claude() {
    case "${1:-}" in
        # Subcomandos e flags informativas não abrem sessão: não há o que ligar.
        mcp|plugin|config|update|doctor|install|migrate-installer|setup-token|agents|auth|--version|-v|--help|-h) ;;
        *)
            local ecc_script="${DOTFILES_DIR:-$HOME/dotfiles}/claude/ecc-project.sh"
            if [[ "${ECC_AUTO:-1}" != 0 && -x "$ecc_script" ]]; then
                # A linha de aviso vai para stderr (não suja a saída de `claude -p`); falha ou demora não bloqueia.
                timeout 5 "$ecc_script" auto "$PWD" >&2 || true
            fi
            ;;
    esac
    command claude "$@"
}
