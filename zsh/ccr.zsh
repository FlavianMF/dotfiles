# ccrc: abre o Claude Code pelo Claude Code Router (CCR), sem tocar no `claude` padrão.
# Sobe o gateway em segundo plano (ccr start) e lança o perfil do Agent Config no modo CLI.
# Argumentos extras vão para o Claude Code.
#
# Variáveis:
#   CCR_PROFILE  nome ou id do perfil do Agent Config (padrão "Claude Code")
ccrc() {
    if ! command -v ccr >/dev/null 2>&1; then
        echo "ccr ausente: rode ./install.sh --with=ccr (ou make ccr-install)" >&2
        return 1
    fi
    ccr start --no-open >/dev/null || { echo "ccr start falhou" >&2; return 1; }
    ccr "${CCR_PROFILE:-Claude Code}" cli -- "$@"
}
