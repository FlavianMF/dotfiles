#!/bin/bash
# Testa herdr/scripts/cockpit-patch.sh num HERDR_APP_HOME temporário: aplica, é idempotente e falha sem
# deixar arquivo parcial quando o upstream muda.
# Uso: bash tests/herdr_cockpit_patch_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UP="$HOME/.claude/plugins/marketplaces/cockpit/app/mods/cockpit"
[[ -f "$UP/activity.js" && -f "$UP/sidebar.js" ]] || { echo "SKIP: upstream do cockpit ausente"; exit 0; }
command -v patch >/dev/null || { echo "SKIP: patch ausente"; exit 0; }
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FALHA: $1"; fail=1; }

tmp="$(mktemp -d)"
trap 'find "$tmp" -mindepth 1 -delete 2>/dev/null; rmdir "$tmp" 2>/dev/null || true' EXIT
export HERDR_APP_HOME="$tmp/app"
mkdir -p "$HERDR_APP_HOME/mods/cockpit"
cp "$UP/activity.js" "$UP/sidebar.js" "$HERDR_APP_HOME/mods/cockpit/"

bash "$ROOT/herdr/scripts/cockpit-patch.sh" --quiet || bad "primeira execução saiu com erro"
grep -q "ADAPTADO para dotfiles" "$HERDR_APP_HOME/mods/cockpit/activity.js" && ok "activity.js com o marcador" || bad "activity.js sem o marcador"
grep -q "quota-box" "$HERDR_APP_HOME/mods/cockpit/sidebar.js" && bad "sidebar.js ainda tem o quota-box" || ok "sidebar.js sem o quota-box"
cmp -s "$HERDR_APP_HOME/mods/cockpit/activity.js" "$ROOT/herdr/app/mods/cockpit/activity.js" && ok "activity.js igual ao do repo" || bad "activity.js difere do repo"

before="$(cksum "$HERDR_APP_HOME"/mods/cockpit/*.js | sort)"
n_bak="$(find "$HERDR_APP_HOME/mods/cockpit" -name '*.bak.*' | wc -l)"
bash "$ROOT/herdr/scripts/cockpit-patch.sh" --quiet || bad "segunda execução saiu com erro"
[[ "$(cksum "$HERDR_APP_HOME"/mods/cockpit/*.js | sort)" == "$before" ]] && ok "segunda execução não muda nada" || bad "segunda execução mudou arquivos"
[[ "$(find "$HERDR_APP_HOME/mods/cockpit" -name '*.bak.*' | wc -l)" == "$n_bak" ]] && ok "segunda execução não cria backup" || bad "segunda execução criou backup"

# Upstream alterado: o patch não aplica, sai com 2 e não toca no arquivo.
cp "$UP/sidebar.js" "$HERDR_APP_HOME/mods/cockpit/sidebar.js"
sed -i 's/quota-box/quota-other/' "$HERDR_APP_HOME/mods/cockpit/sidebar.js"
snap="$(cksum "$HERDR_APP_HOME/mods/cockpit/sidebar.js")"
bash "$ROOT/herdr/scripts/cockpit-patch.sh" --quiet 2>/dev/null; rc=$?
[[ "$rc" == 2 ]] && ok "upstream alterado sai com 2" || bad "upstream alterado saiu com $rc"
[[ "$(cksum "$HERDR_APP_HOME/mods/cockpit/sidebar.js")" == "$snap" ]] && ok "arquivo intacto na falha" || bad "arquivo mudou na falha"

((fail)) && exit 1
echo "ok: herdr_cockpit_patch_test"
