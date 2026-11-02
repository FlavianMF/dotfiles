#!/bin/bash
# Testes automatizados do catalogo de comandos do HASS.Agent (commands.json)
# Uso: bash tests/hass_agent_commands_test.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMANDS_JSON="$ROOT/powershell/hass-agent/commands.json"

fail=0
expect() {
    if [[ "$2" != "$3" ]]; then
        echo "❌ FALHA: $1 (obtido: '$2', esperado: '$3')"
        fail=1
    else
        echo "✅ PASSOU: $1"
    fi
}

has() {
    if ! grep -F -q -- "$2" <<<"$3"; then
        echo "❌ FALHA: $1 (faltou '$2' em: $3)"
        fail=1
    else
        echo "✅ PASSOU: $1"
    fi
}

# 1. Existência do arquivo
if [[ ! -f "$COMMANDS_JSON" ]]; then
    echo "❌ FALHA: commands.json não encontrado em $COMMANDS_JSON"
    exit 1
fi
echo "✅ PASSOU: arquivo commands.json existe"

# 2. Sintaxe JSON válida
if jq empty "$COMMANDS_JSON" >/dev/null 2>&1; then
    echo "✅ PASSOU: commands.json é um JSON válido"
else
    echo "❌ FALHA: commands.json contém erro de sintaxe JSON"
    fail=1
fi

# 3. Nenhum caminho $HOME/dotfiles restante
if grep -F -q '$HOME/dotfiles' "$COMMANDS_JSON"; then
    echo "❌ FALHA: commands.json ainda contém caminhos inválidos \$HOME/dotfiles"
    fail=1
else
    echo "✅ PASSOU: nenhum caminho \$HOME/dotfiles restante"
fi

# 4. Presença dos 4 botões de perfil de energia
for profile in eco balanced llm_boost max; do
    id="pc_mode_${profile}"
    count="$(jq -r --arg id "$id" '[.commands[] | select(.id == $id)] | length' "$COMMANDS_JSON")"
    expect "botão $id está presente" "$count" "1"

    # Validação do comando: grava em C:\ProgramData\pc-ctl\request.json e aciona schtasks
    args="$(jq -r --arg id "$id" '.commands[] | select(.id == $id) | .arguments' "$COMMANDS_JSON")"
    has "$id grava em request.json" 'C:\ProgramData\pc-ctl\request.json' "$args"
    has "$id aciona tarefa agendada pc-ctl-power" 'schtasks.exe -ArgumentList '\''/run'\'','\''/tn'\'','\''pc-ctl-power'\''' "$args"
done

# 5. Validação do botão Claude Code no WSL2
claude_args="$(jq -r '.commands[] | select(.id == "pc_wsl_claude") | .arguments' "$COMMANDS_JSON")"
has "pc_wsl_claude usa diretório ~/dotfiles" "--cd ~/dotfiles" "$claude_args"

# 6. Presença de comandos essenciais de energia e sessão
for essential in pc_shutdown pc_shutdown_abort pc_restart pc_sleep pc_lock; do
    count="$(jq -r --arg id "$essential" '[.commands[] | select(.id == $id)] | length' "$COMMANDS_JSON")"
    expect "comando essencial $essential presente" "$count" "1"
done

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de commands.json PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste de commands.json."
fi
exit $fail
