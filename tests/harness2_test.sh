#!/bin/bash
# Testes de harness2/install.sh (unitário e sem rede).
# Uso: bash tests/harness2_test.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

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

INSTALLER="$ROOT/harness2/install.sh"

# 1. Existência e permissão
if [[ ! -f "$INSTALLER" ]]; then
    echo "❌ FALHA: harness2/install.sh não existe"
    exit 1
fi

if [[ ! -x "$INSTALLER" ]]; then
    echo "❌ FALHA: harness2/install.sh não tem permissão de execução"
    fail=1
fi

# 2. Help
out_help="$(bash "$INSTALLER" --help 2>&1)"
has "help exibe uso" "Uso: harness2/install.sh" "$out_help"
has "help documenta dry-run" "--dry-run" "$out_help"
has "help documenta update" "--update" "$out_help"

# 3. Opção desconhecida
out_unknown="$(bash "$INSTALLER" --flag-invalida 2>&1)"
rc_unknown=$?
expect "opcao desconhecida sai com 2" "$rc_unknown" "2"
has "mensagem de opcao desconhecida" "Opção desconhecida" "$out_unknown"

# 4. Dry-run com repositório novo
out_dry="$(HARNESS2_HOME="$tmp/harness2-novo" bash "$INSTALLER" --dry-run 2>&1)"
has "dry-run indica clonagem" "Clonaria" "$out_dry"
has "dry-run indica venv" "Criaria/validaria venv" "$out_dry"
has "dry-run indica pacote" "-e '.[render,bridge]'" "$out_dry"

# 5. Instalação simulada em sandbox
mkdir -p "$tmp/bin" "$tmp/home/.local/bin" "$tmp/repo"
cat >"$tmp/bin/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "clone" ]]; then
    mkdir -p "$3/.git"
    touch "$3/pyproject.toml"
    exit 0
elif [[ "$1" == "-C" ]]; then
    exit 0
fi
exit 0
MOCK
chmod +x "$tmp/bin/git"

cat >"$tmp/bin/uv" <<'MOCK'
#!/bin/bash
if [[ "$1" == "venv" ]]; then
    target="$2"
    mkdir -p "$target/bin"
    touch "$target/bin/python"
    chmod +x "$target/bin/python"
    for b in harness2 harness2-setup harness2-check harness2-demo harness2-judge harness2-report harness2-bridge; do
        cat >"$target/bin/$b" <<EOF_B
#!/bin/bash
echo "$b mock"
EOF_B
        chmod +x "$target/bin/$b"
    done
    exit 0
elif [[ "$1" == "pip" && "$2" == "install" ]]; then
    exit 0
fi
exit 0
MOCK
chmod +x "$tmp/bin/uv"

export PATH="$tmp/bin:$PATH"
export HOME="$tmp/home"

out_install="$(HARNESS2_HOME="$tmp/harness2-sandbox" HARNESS2_BIN_DIR="$tmp/home/.local/bin" bash "$INSTALLER" 2>&1)"
rc_install=$?
expect "instalacao sai com 0" "$rc_install" "0"
has "instalacao reporta sucesso" "Harness² instalado com sucesso" "$out_install"

# Verifica se os executáveis foram vinculados em ~/.local/bin
for b in harness2 harness2-setup harness2-check harness2-demo harness2-judge harness2-report harness2-bridge; do
    if [[ -x "$tmp/home/.local/bin/$b" ]]; then
        echo "✅ PASSOU: link de $b criado em bin_dir"
    else
        echo "❌ FALHA: link de $b não encontrado em bin_dir"
        fail=1
    fi
done

# 6. Idempotência / re-execução
out_reinstall="$(HARNESS2_HOME="$tmp/harness2-sandbox" HARNESS2_BIN_DIR="$tmp/home/.local/bin" bash "$INSTALLER" 2>&1)"
rc_reinstall=$?
expect "re-execucao sai com 0" "$rc_reinstall" "0"
has "re-execucao reconhece repositorio existente" "Repositório Harness² encontrado" "$out_reinstall"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de harness2/install.sh PASSARAM!"
    exit 0
else
    echo "❌ Alguns testes falharam."
    exit 1
fi
