#!/bin/bash
# Testes de claude/ecc-detect.sh. Uso: bash tests/ecc_detect_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$ROOT/claude/ecc-detect.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0

# case_ <nome> <esperado> <setup...>: cria um diretório novo, roda o setup (função) e compara.
check() { # check <nome> <esperado> <dir>
    local got; got="$(bash "$DETECT" "$3")"
    if [[ "$got" != "$2" ]]; then echo "FALHA: $1 (obtido '$got', esperado '$2')"; fail=1; fi
}
mk() { mkdir -p "$tmp/$1"; echo "$tmp/$1"; }
pkg() { printf '{"dependencies":{%s}}' "$2" >"$1/package.json"; }

d="$(mk next)";      pkg "$d" '"next":"14","react":"18"';           check "next" "web web,typescript,react" "$d"
d="$(mk vitevue)";   pkg "$d" '"vue":"3"' ; echo '"vite": "5"' >>"$d/package.json"; check "vue+vite" "web web,typescript,vue" "$d"
d="$(mk nuxt)";      pkg "$d" '"nuxt":"3","vue":"3"';              check "nuxt" "web web,typescript,nuxt,vue" "$d"
d="$(mk angular)";   pkg "$d" '"@angular/core":"17"';              check "angular" "web web,typescript,angular" "$d"
d="$(mk astro)";     pkg "$d" '"astro":"4"';                       check "astro" "web web,typescript" "$d"
d="$(mk html)";      echo '<html>' >"$d/index.html";               check "index.html" "web web,typescript" "$d"
d="$(mk tsx)";       echo '{}' >"$d/tsconfig.json"; mkdir "$d/src"; : >"$d/src/App.tsx"; check "tsconfig+tsx" "web web,typescript" "$d"
d="$(mk mono)";      mkdir -p "$d/apps/site"; pkg "$d/apps/site" '"react":"18"'; echo '{"workspaces":["apps/*"]}' >"$d/package.json"; check "monorepo" "web web,typescript,react" "$d"
d="$(mk express)";   pkg "$d" '"express":"4"';                     check "backend express" "node" "$d"
d="$(mk tooling)";   pkg "$d" '"prettier":"3"';                    check "package.json só de tooling" "none" "$d"
d="$(mk cmakec)";    printf 'cmake_minimum_required(VERSION 3.20)\nproject(foo\n  LANGUAGES C)\n' >"$d/CMakeLists.txt"; check "cmake C" "c" "$d"
d="$(mk cmakecxx)";  printf 'project(foo LANGUAGES C CXX)\n' >"$d/CMakeLists.txt"; check "cmake C CXX" "none" "$d"
d="$(mk cmakedef)";  printf 'project(foo)\n' >"$d/CMakeLists.txt"; check "cmake sem linguagens" "none" "$d"
d="$(mk meson)";     printf "project('x', 'c')\n" >"$d/meson.build"; check "meson c" "c" "$d"
d="$(mk mesoncpp)";  printf "project('x', 'c', 'cpp')\n" >"$d/meson.build"; check "meson c+cpp" "none" "$d"
d="$(mk makec)";     : >"$d/Makefile"; : >"$d/main.c";             check "Makefile+c" "c" "$d"
d="$(mk makeonly)";  : >"$d/Makefile";                             check "Makefile sem fontes" "none" "$d"
d="$(mk mixed)";     : >"$d/Makefile"; : >"$d/a.c"; : >"$d/b.cpp"; check "misto C/C++" "none" "$d"
d="$(mk cdeep)";     : >"$d/Makefile"; mkdir -p "$d/src"; : >"$d/src/a.c"; mkdir -p "$d/node_modules/x"; : >"$d/node_modules/x/y.cpp"; check "node_modules ignorado" "c" "$d"
d="$(mk empty)";                                                   check "vazio" "none" "$d"
check "diretório inexistente" "none" "$tmp/nao-existe"

# Desempenho: cada execução abaixo de 50 ms em média (100 execuções).
d="$(mk perf)"; pkg "$d" '"next":"14"'
start=$(date +%s%N); for _ in $(seq 100); do bash "$DETECT" "$d" >/dev/null; done; end=$(date +%s%N)
avg=$(( (end - start) / 100 / 1000000 ))
[[ $avg -lt 50 ]] || { echo "FALHA: média ${avg} ms por execução"; fail=1; }

[[ $fail -eq 0 ]] && echo "ok" || exit 1
