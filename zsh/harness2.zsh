# Integration for Harness² (Recursive Agent Harnessing Framework)
# Repositório padrão: ~/projetos_harness/harness2

export HARNESS2_HOME="${HARNESS2_HOME:-$HOME/projetos_harness/harness2}"

# Adiciona o venv do Harness² ao PATH se instalado
if [[ -d "$HARNESS2_HOME/.venv/bin" ]]; then
    case ":$PATH:" in
        *":$HARNESS2_HOME/.venv/bin:"*) ;;
        *) export PATH="$HARNESS2_HOME/.venv/bin:$PATH" ;;
    esac
fi

# Atalhos úteis
harness2-cd() {
    builtin cd "$HARNESS2_HOME"
}

harness2-venv() {
    if [[ -f "$HARNESS2_HOME/.venv/bin/activate" ]]; then
        source "$HARNESS2_HOME/.venv/bin/activate"
    else
        echo "Venv do Harness² não encontrado em $HARNESS2_HOME/.venv (rode ./install.sh --with=harness2 ou make harness2-install)" >&2
        return 1
    fi
}
