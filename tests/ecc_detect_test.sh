#!/bin/bash
# Testes de claude/ecc-detect.sh. Uso: bash tests/ecc_detect_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$ROOT/claude/ecc-detect.sh"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
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

# Casos de borda apontados na revisão.
d="$(mk backdev)";   echo '{"dependencies":{"express":"4"},"devDependencies":{"react":"18"}}' >"$d/package.json"; check "backend com react só em devDependencies" "node" "$d"
d="$(mk frontdev)";  echo '{"devDependencies":{"vite":"5"}}' >"$d/package.json"; check "vite só em devDependencies" "web web,typescript" "$d"
d="$(mk script)";    echo '{"scripts":{"vite":"vite build"},"description":"uses react and vue"}' >"$d/package.json"; check "nome em script/descrição não conta" "none" "$d"
d="$(mk peer)";      echo '{"peerDependencies":{"express":"4"}}' >"$d/package.json"; check "express só em peerDependencies" "none" "$d"
d="$(mk rn)";        pkg "$d" '"react-native":"0.7"'; check "react-native não é web" "none" "$d"
d="$(mk cmakever)";  printf 'project(foo VERSION 1 DESCRIPTION "a C lib")\n' >"$d/CMakeLists.txt"; check "cmake VERSION/DESCRIPTION sem linguagens" "none" "$d"
d="$(mk cmakeold)";  printf 'project(foo C)\n' >"$d/CMakeLists.txt"; check "cmake forma antiga C" "c" "$d"
d="$(mk cmakeold2)"; printf 'project(foo CXX C)\n' >"$d/CMakeLists.txt"; check "cmake forma antiga CXX C" "none" "$d"
d="$(mk cmakecmt)";  printf '# project(x CXX)\nproject(foo C)\n' >"$d/CMakeLists.txt"; check "cmake comentário antes" "c" "$d"
d="$(mk mesonq)";    printf 'project("x", "c")\n' >"$d/meson.build"; check "meson aspas duplas" "c" "$d"
d="$(mk pyext)";     : >"$d/Makefile"; mkdir "$d/src"; : >"$d/src/ext.c"; : >"$d/pyproject.toml"; check "extensão C em projeto Python" "none" "$d"
d="$(mk builder)";   : >"$d/Makefile"; : >"$d/builder.c"; check "arquivo build* não é pruned" "c" "$d"
d="$(mk nmdepth2)";  : >"$d/Makefile"; : >"$d/main.c"; mkdir "$d/node_modules"; : >"$d/node_modules/y.cpp"; check "node_modules prunado no nível 2" "c" "$d"
d="$(mk "sp ace é")"; pkg "$d" '"react":"18"'; check "caminho com espaço e acento" "web web,typescript,react" "$d"
mkdir -p "$tmp/-dash"; pkg "$tmp/-dash" '"react":"18"'; got="$(cd "$tmp" && bash "$DETECT" -dash)"; [[ "$got" == "web web,typescript,react" ]] || { echo "FALHA: dir relativo com hífen ($got)"; fail=1; }

# Desempenho: média por execução abaixo de 150 ms (50 execuções; a margem cobre máquina carregada).
d="$(mk perf)"; pkg "$d" '"next":"14"'
start=$(date +%s%N); for _ in $(seq 50); do bash "$DETECT" "$d" >/dev/null; done; end=$(date +%s%N)
avg=$(( (end - start) / 50 / 1000000 ))
[[ $avg -lt 150 ]] || { echo "FALHA: média ${avg} ms por execução"; fail=1; }

[[ $fail -eq 0 ]] && echo "ok" || exit 1
