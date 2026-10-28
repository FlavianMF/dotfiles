#!/bin/bash
# Testes de ccr/install.sh, traycer/install.sh e zsh/ccr.zsh. Uso: bash tests/ccr_traycer_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

mkdir "$tmp/bin" "$tmp/home"
# curl falso: grava um arquivo fixo no destino de -o e nunca toca a rede.
# A URL do modelo STT recebe o fixture .tar.bz2; qualquer outra recebe o AppImage falso.
# Cada URL do modelo STT pedida fica registrada em $CURL_LOG.
cat >"$tmp/bin/curl" <<'FAKE'
#!/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && { out="$2"; shift; }; url="$1"; shift; done
if [[ "$url" == *sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2 ]]; then
    printf '%s\n' "$url" >>"$CURL_LOG"
    cp "$STT_FIXTURE" "$out"
else
    printf 'fake-appimage' >"$out"
fi
FAKE
chmod +x "$tmp/bin/curl"
# Fixture do modelo STT: tar.bz2 pequeno com os 4 arquivos esperados.
stt_arch=sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8
mkdir -p "$tmp/fixture/$stt_arch"
for f in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
    printf 'fake-%s' "$f" >"$tmp/fixture/$stt_arch/$f"
done
tar -cjf "$tmp/stt.tar.bz2" -C "$tmp/fixture" "$stt_arch"
stt_sha="$(sha256sum "$tmp/stt.tar.bz2" | cut -d' ' -f1)"
export STT_FIXTURE="$tmp/stt.tar.bz2" CURL_LOG="$tmp/curl.log"; : >"$CURL_LOG"
stt_dir="$tmp/home/.traycer/models/stt/parakeet-tdt-0.6b-v3"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH"

# --- Traycer ---
out="$(bash "$ROOT/traycer/install.sh" --dry-run 2>&1)"
has "dry-run baixa" "download" "$out"
has "dry-run instala o launcher" "$HOME/.local/bin/traycer" "$out"
[[ ! -e "$HOME/.local/bin/traycer" ]] || { echo "FALHA: dry-run criou o launcher"; fail=1; }
has "dry-run baixa o modelo STT ausente" "\[dry-run\] download .*parakeet-tdt-0.6b-v3" "$out"
[[ ! -e "$stt_dir" ]] || { echo "FALHA: dry-run criou o diretório do modelo STT"; fail=1; }

# apt e sudo falsos: registram a chamada. Só o caso sem libfuse.so.2 real instala o pacote.
cat >"$tmp/bin/sudo" <<'FAKE'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$APT_LOG"
FAKE
cat >"$tmp/bin/apt-get" <<'FAKE'
#!/bin/bash
printf 'apt-get:%s\n' "$*" >>"$APT_LOG"
FAKE
cat >"$tmp/bin/apt-cache" <<'FAKE'
#!/bin/bash
[[ "$2" == libfuse2t64 ]]
FAKE
chmod +x "$tmp/bin/sudo" "$tmp/bin/apt-get" "$tmp/bin/apt-cache"
export APT_LOG="$tmp/apt.log"; : >"$APT_LOG"
if ! /sbin/ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    out="$(bash "$ROOT/traycer/install.sh" --dry-run 2>&1)"
    has "dry-run instala libfuse2t64" "apt-get install -y libfuse2t64" "$out"
fi

# Cópia do instalador com um SHA256 que não bate.
cp -r "$ROOT/traycer" "$tmp/tr"
out="$(bash "$tmp/tr/install.sh" 2>&1)"; rc=$?
expect "hash errado falha" "$rc" "1"
has "hash errado explica" "sha256 mismatch" "$out"
[[ ! -e "$HOME/.local/opt/traycer/traycer.AppImage" ]] || { echo "FALHA: instalou com hash errado"; fail=1; }

# --update regrava o hash sem instalar; depois o install passa.
bash "$tmp/tr/install.sh" --update >/dev/null 2>&1
expect "update grava o sha256 do download" "$(cut -d' ' -f1 "$tmp/tr/SHA256")" "$(printf 'fake-appimage' | sha256sum | cut -d' ' -f1)"
[[ ! -e "$HOME/.local/bin/traycer" ]] || { echo "FALHA: --update instalou"; fail=1; }
bash "$tmp/tr/install.sh" >/dev/null 2>&1; expect "install com hash certo" "$?" "0"
if ! /sbin/ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    has "install pede libfuse2t64 via sudo apt-get" "sudo:apt-get install -y libfuse2t64" "$(cat "$APT_LOG")"
fi
[[ -x "$HOME/.local/opt/traycer/traycer.AppImage" && -x "$HOME/.local/bin/traycer" ]] || { echo "FALHA: arquivos instalados ausentes"; fail=1; }

# Launcher: sem libfuse.so.2 liga APPIMAGE_EXTRACT_AND_RUN; com a biblioteca não liga.
cat >"$HOME/.local/opt/traycer/traycer.AppImage" <<'FAKEAPP'
#!/bin/bash
echo "extract=${APPIMAGE_EXTRACT_AND_RUN:-0}"
FAKEAPP
if [[ -e /dev/fuse && -x /sbin/ldconfig ]]; then
    # ldconfig falso via PATH não vale: o launcher chama /sbin/ldconfig; o teste só roda sem a lib real.
    if ! /sbin/ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
        expect "launcher sem libfuse2 extrai e roda" "$("$HOME/.local/bin/traycer")" "extract=1"
    else
        expect "launcher com libfuse2 monta" "$("$HOME/.local/bin/traycer")" "extract=0"
    fi
fi

# --- Modelo STT (parakeet-tdt-0.6b-v3) ---
stt_files=(encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt)
# Sem modelo: o install com hash default (que não bate com o fixture) só avisa; o AppImage instala.
for f in "${stt_files[@]}"; do
    [[ ! -e "$stt_dir/$f" ]] || { echo "FALHA: modelo STT instalado com hash default ($f)"; fail=1; }
done
# TRAYCER_STT_SHA256 errado: o modelo não é instalado, mas o AppImage sim.
rm -f "$HOME/.local/opt/traycer/traycer.AppImage" "$HOME/.local/bin/traycer"
out="$(TRAYCER_STT_SHA256=0000 bash "$tmp/tr/install.sh" 2>&1)"; rc=$?
expect "hash STT errado não falha o install" "$rc" "0"
has "hash STT errado explica" "sha256 mismatch for $stt_arch.tar.bz2" "$out"
has "hash STT errado avisa" "WARNING: could not install Traycer STT model" "$out"
[[ -x "$HOME/.local/opt/traycer/traycer.AppImage" && -x "$HOME/.local/bin/traycer" ]] || { echo "FALHA: AppImage não instalado com hash STT errado"; fail=1; }
for f in "${stt_files[@]}"; do
    [[ ! -e "$stt_dir/$f" ]] || { echo "FALHA: modelo STT instalado com hash errado ($f)"; fail=1; }
done
# TRAYCER_STT_SHA256 certo: extrai os 4 arquivos.
: >"$CURL_LOG"
out="$(TRAYCER_STT_SHA256="$stt_sha" bash "$tmp/tr/install.sh" 2>&1)"; rc=$?
expect "install com hash STT certo" "$rc" "0"
has "install anuncia o modelo STT" "Installed Traycer STT model" "$out"
for f in "${stt_files[@]}"; do
    [[ -s "$stt_dir/$f" ]] || { echo "FALHA: modelo STT sem $f"; fail=1; }
done
expect "conteúdo do modelo STT extraído" "$(cat "$stt_dir/tokens.txt")" "fake-tokens.txt"
expect "install baixou o modelo STT uma vez" "$(wc -l <"$CURL_LOG")" "1"
# Com os 4 arquivos presentes: dry-run informa e o install não baixa de novo.
out="$(bash "$tmp/tr/install.sh" --dry-run 2>&1)"
has "dry-run reconhece o modelo STT instalado" "Traycer STT model already installed: $stt_dir" "$out"
if grep -q "download .*parakeet-tdt-0.6b-v3" <<<"$out"; then echo "FALHA: dry-run baixaria o modelo STT já instalado"; fail=1; fi
: >"$CURL_LOG"
out="$(TRAYCER_STT_SHA256="$stt_sha" bash "$tmp/tr/install.sh" 2>&1)"; rc=$?
expect "reinstall com modelo STT presente" "$rc" "0"
has "reinstall pula o modelo STT" "Traycer STT model already installed: $stt_dir" "$out"
expect "reinstall não baixa o modelo STT" "$(wc -l <"$CURL_LOG")" "0"
# Modelo incompleto (arquivo vazio) volta a ser baixado.
: >"$stt_dir/joiner.int8.onnx"
out="$(TRAYCER_STT_SHA256="$stt_sha" bash "$tmp/tr/install.sh" 2>&1)"
has "modelo STT incompleto é baixado de novo" "Installed Traycer STT model" "$out"
[[ -s "$stt_dir/joiner.int8.onnx" ]] || { echo "FALHA: joiner.int8.onnx não restaurado"; fail=1; }
# Falha ao gravar o modelo: o install sai com 0, avisa e não anuncia sucesso.
stt_write_fail() {
    out="$(TRAYCER_STT_SHA256="$stt_sha" bash "$tmp/tr/install.sh" 2>&1)"; rc=$?
    expect "$1: o install não falha" "$rc" "0"
    has "$1: avisa" "WARNING: could not install Traycer STT model" "$out"
    if grep -q "Installed Traycer STT model" <<<"$out"; then echo "FALHA: $1: anunciou um modelo que não gravou"; fail=1; fi
}
rm -r "$stt_dir"; : >"$stt_dir"
stt_write_fail "arquivo no lugar do diretório do modelo STT"
rm "$stt_dir"
if [[ $EUID -ne 0 ]]; then
    mkdir "$stt_dir"; chmod 555 "$stt_dir"
    stt_write_fail "diretório do modelo STT sem escrita"
    chmod 755 "$stt_dir"; rmdir "$stt_dir"
fi

# Sem SHA256 o install falha.
rm "$tmp/tr/SHA256"
bash "$tmp/tr/install.sh" >/dev/null 2>&1; expect "sem SHA256 falha" "$?" "1"

# --- CCR ---
expect "VERSION é semver" "$(grep -c -E '^[0-9]+\.[0-9]+\.[0-9]+$' "$ROOT/ccr/VERSION")" "1"
bash "$ROOT/ccr/install.sh" --update "abc" >/dev/null 2>&1; expect "--update rejeita versão inválida" "$?" "2"
if command -v npm >/dev/null && [[ "$(node -v | sed -E 's/^v([0-9]+).*/\1/')" -ge 22 ]]; then
    out="$(CCR_PREFIX="$tmp/prefix" bash "$ROOT/ccr/install.sh" --dry-run 2>&1)"
    has "dry-run fixa a versão" "claude-code-router@$(tr -d '[:space:]' <"$ROOT/ccr/VERSION")" "$out"
fi

# --- ccrc ---
if command -v zsh >/dev/null; then
    cat >"$tmp/bin/ccr" <<'FAKE'
#!/bin/bash
printf 'ccr:%s\n' "$*" >>"$CCR_LOG"
FAKE
    chmod +x "$tmp/bin/ccr"
    export CCR_LOG="$tmp/ccr.log"
    zsh -c 'source "$1/zsh/ccr.zsh"; ccrc --model sonnet' zsh "$ROOT" >/dev/null 2>&1
    expect "ccrc sobe o gateway e lança o perfil" "$(cat "$CCR_LOG")" $'ccr:start --no-open\nccr:Claude Code cli -- --model sonnet'
    : >"$CCR_LOG"
    CCR_PROFILE=outro zsh -c 'source "$1/zsh/ccr.zsh"; ccrc' zsh "$ROOT" >/dev/null 2>&1
    expect "CCR_PROFILE troca o perfil" "$(tail -1 "$CCR_LOG")" "ccr:outro cli --"
    rm "$tmp/bin/ccr"
    # PATH enxuto: um ccr real em ~/.local/bin não pode vazar para o teste.
    out="$(PATH=/usr/bin:/bin zsh -c 'source "$1/zsh/ccr.zsh"; ccrc' zsh "$ROOT" 2>&1)"; rc=$?
    expect "ccrc sem ccr falha" "$rc" "1"
    has "ccrc sem ccr avisa" "ccr ausente" "$out"
fi

[[ $fail -eq 0 ]] && echo "ccr_traycer_test: ok"
exit $fail
