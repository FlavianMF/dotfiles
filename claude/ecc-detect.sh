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
cd "$dir" 2>/dev/null || { echo none; exit 0; }

FRONT_RE='"(next|vite|react|vue|nuxt|@angular/core|svelte|@sveltejs/kit|astro)"[[:space:]]*:'
BACK_RE='"(express|fastify|koa|@nestjs/core|@hapi/hapi|hono|restify|apollo-server|@apollo/server|@trpc/server)"[[:space:]]*:'

# package.json da raiz e de apps/* e packages/* (monorepo).
package_files() {
    local f
    for f in package.json apps/*/package.json packages/*/package.json; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done
}

# find limitado: imprime o primeiro arquivo que casa com os -name dados.
first_file() {
    find . -maxdepth 2 \( -name node_modules -o -name .git -o -name 'build*' -o -name dist -o -name vendor \) -prune \
        -o -type f \( "$@" \) -print -quit 2>/dev/null
}

classify() {
    local pkgs deps packs
    mapfile -t pkgs < <(package_files)
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        deps="$(cat "${pkgs[@]}" 2>/dev/null)"
        if grep -qE "$FRONT_RE" <<<"$deps"; then
            packs="web,typescript"
            grep -qE '"(react|next)"[[:space:]]*:' <<<"$deps" && packs+=",react"
            grep -qE '"nuxt"[[:space:]]*:' <<<"$deps" && packs+=",nuxt,vue"
            grep -qE '"vue"[[:space:]]*:' <<<"$deps" && ! grep -qE '"nuxt"[[:space:]]*:' <<<"$deps" && packs+=",vue"
            grep -qE '"@angular/core"[[:space:]]*:' <<<"$deps" && packs+=",angular"
            echo "web $packs"; return
        fi
    fi
    if [[ -f index.html || -f public/index.html || -f src/index.html ]]; then
        echo "web web,typescript"; return
    fi
    if [[ -f tsconfig.json && -n "$(first_file -name '*.tsx' -o -name '*.vue' -o -name '*.svelte')" ]]; then
        echo "web web,typescript"; return
    fi
    if [[ ${#pkgs[@]} -gt 0 ]] && grep -qE "$BACK_RE" <<<"$deps"; then
        echo node; return
    fi

    # C puro: C++ em qualquer lugar até 2 níveis descarta (misto vira none).
    [[ -z "$(first_file -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' -o -name '*.hpp')" ]] || { echo none; return; }
    if [[ -f CMakeLists.txt ]]; then
        local project
        project="$(tr '\n' ' ' <CMakeLists.txt | grep -oiE 'project[[:space:]]*\([^)]*\)')"
        if grep -qiE '(^|[[:space:](])C([[:space:])]|$)' <<<"$project" && ! grep -qiE 'CXX' <<<"$project"; then
            echo c; return
        fi
    fi
    if [[ -f meson.build ]]; then
        local meson
        meson="$(tr '\n' ' ' <meson.build | grep -oE "project[[:space:]]*\([^)]*\)")"
        grep -qE "'c'" <<<"$meson" && ! grep -qE "'cpp'" <<<"$meson" && { echo c; return; }
    fi
    if [[ -f Makefile || -f compile_commands.json ]] && [[ -n "$(first_file -name '*.c' -o -name '*.h')" ]]; then
        echo c; return
    fi
    echo none
}

classify
exit 0
