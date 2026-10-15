#!/bin/bash
# Classifica um projeto para o ECC automático. Imprime uma linha e sai sempre com 0:
#   web <packs>   projeto web; packs do ECC separados por vírgula (web,typescript + o do framework)
#   node          backend Node (sem framework de front)
#   c             projeto em C puro (sem C++)
#   none          qualquer outro caso, inclusive misto C/C++ e dúvida
#
# Uso: claude/ecc-detect.sh [dir]
# Só usa [[ -f ]], grep e um find limitado a 2 níveis (sem node_modules, .git, build*, dist,
# vendor), então não depende de jq e custa poucos milissegundos.
dir="${1:-.}"
cd -- "$dir" 2>/dev/null || { echo none; exit 0; }


# package.json da raiz e de apps/* e packages/* (monorepo), sem os maiores que 1 MB (um fork só).
package_files() {
    local cands=() f
    for f in package.json apps/*/package.json packages/*/package.json; do
        [[ -f "$f" ]] && cands+=("$f")
    done
    [[ ${#cands[@]} -gt 0 ]] && find "${cands[@]}" -maxdepth 0 -size -1025k -print 2>/dev/null
}

# Preenche PROD[nome] (dependencies + optionalDependencies) e DEV[nome] (devDependencies) a partir dos
# package.json, lendo só chaves de dependência (um script ou descrição chamados "vite" não contam).
declare -A PROD DEV
load_deps() {
    local kind name
    if command -v jq >/dev/null 2>&1; then
        while read -r kind name; do
            [[ "$kind" == P ]] && PROD["$name"]=1
            [[ "$kind" == D ]] && DEV["$name"]=1
        done < <(jq -r '((.dependencies // {}) + (.optionalDependencies // {}) | keys[]? | "P " + .), ((.devDependencies // {}) | keys[]? | "D " + .)' "$@" 2>/dev/null)
    else
        # Sem jq: qualquer chave "nome": dos arquivos conta como dependência de produção (aproximação).
        while read -r name; do PROD["$name"]=1; done < <(grep -ohE '"[@A-Za-z0-9/_.-]+"[[:space:]]*:' "$@" 2>/dev/null | sed -E 's/^"([^"]+)".*/\1/')
    fi
}

FRONT_NAMES=(next vite react vue nuxt @angular/core svelte @sveltejs/kit astro)
BACK_NAMES=(express fastify koa @nestjs/core @hapi/hapi hono restify apollo-server @apollo/server @trpc/server)
any_of() { # any_of <PROD|DEV|ANY> <nomes...>
    local group="$1" n; shift
    for n in "$@"; do
        case "$group" in
            PROD) [[ -n "${PROD[$n]:-}" ]] && return 0 ;;
            DEV)  [[ -n "${DEV[$n]:-}" ]] && return 0 ;;
            ANY)  [[ -n "${PROD[$n]:-}${DEV[$n]:-}" ]] && return 0 ;;
        esac
    done
    return 1
}

# find limitado: imprime o primeiro arquivo que casa com os -name dados.
first_file() {
    find . -maxdepth 2 \( -name node_modules -o -name .git -o -name 'build*' -o -name dist -o -name vendor \) -type d -prune \
        -o -type f \( "$@" \) -print -quit 2>/dev/null
}

# Linguagens do primeiro project() do CMakeLists.txt, uma por linha: depois de LANGUAGES, ou os
# argumentos posicionais depois do nome (forma antiga). Comentários e textos entre aspas não contam.
cmake_languages() {
    sed 's/#.*//' CMakeLists.txt | tr '\n' ' ' | sed 's/"[^"]*"//g' \
        | grep -oiE 'project[[:space:]]*\([^)]*\)' | head -n 1 \
        | sed -E 's/^[^(]*\(//; s/\)$//' | tr -s '[:space:]' '\n' | awk '
            NR == 1 { next }
            toupper($0) == "LANGUAGES" { seen = 1; next }
            toupper($0) == "VERSION" && !seen { skip = 1; next }
            toupper($0) ~ /^(DESCRIPTION|HOMEPAGE_URL)$/ { next }
            skip { skip = 0; next }
            { print toupper($0) }'
}

classify() {
    local pkgs packs
    mapfile -t pkgs < <(package_files)
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        load_deps "${pkgs[@]}"
        # Front em dependencies, ou só em devDependencies sem servidor: web. Servidor com front só de dev (storybook, testes): backend.
        if any_of PROD "${FRONT_NAMES[@]}" || { any_of DEV "${FRONT_NAMES[@]}" && ! any_of PROD "${BACK_NAMES[@]}"; }; then
            packs="web,typescript"
            any_of ANY react next && packs+=",react"
            any_of ANY nuxt && packs+=",nuxt,vue"
            any_of ANY vue && ! any_of ANY nuxt && packs+=",vue"
            any_of ANY @angular/core && packs+=",angular"
            echo "web $packs"; return
        fi
    fi
    if [[ -f index.html || -f public/index.html || -f src/index.html ]]; then
        echo "web web,typescript"; return
    fi
    if [[ -f tsconfig.json && -n "$(first_file -name '*.tsx' -o -name '*.vue' -o -name '*.svelte')" ]]; then
        echo "web web,typescript"; return
    fi
    if [[ ${#pkgs[@]} -gt 0 ]] && any_of PROD "${BACK_NAMES[@]}"; then
        echo node; return
    fi

    # C puro: C++ em qualquer lugar até 2 níveis descarta (misto vira none).
    [[ -z "$(first_file -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' -o -name '*.hpp')" ]] || { echo none; return; }
    if [[ -f CMakeLists.txt ]]; then
        local langs
        langs="$(cmake_languages)"
        grep -qwx 'C' <<<"$langs" && ! grep -qwx 'CXX' <<<"$langs" && { echo c; return; }
    fi
    if [[ -f meson.build ]]; then
        local meson
        meson="$(tr '\n' ' ' <meson.build | grep -oE "project[[:space:]]*\([^)]*\)" | head -n 1)"
        grep -qE "['\"]c['\"]" <<<"$meson" && ! grep -qE "['\"]cpp['\"]" <<<"$meson" && { echo c; return; }
    fi
    # Makefile com .c/.h só vale quando não há manifesto de outra linguagem (extensão C em projeto Python, Go...).
    if [[ -f Makefile || -f compile_commands.json ]] && [[ -n "$(first_file -name '*.c' -o -name '*.h')" ]] \
        && ! [[ -f go.mod || -f Cargo.toml || -f pyproject.toml || -f setup.py || -f pom.xml || -f build.gradle || -f package.json ]]; then
        echo c; return
    fi
    echo none
}

classify
exit 0
