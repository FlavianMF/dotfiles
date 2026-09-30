---
paths:
  - "**/Makefile"
  - "**/makefile"
  - "**/GNUmakefile"
  - "**/*.mk"
---
# Makefile (regra local do dotfiles, não vem do ECC)

- Receitas são indentadas com **TAB**, não espaços; preserve isso ao editar.
- Declare em `.PHONY` todo alvo que não gera um arquivo com o mesmo nome (`all`, `clean`,
  `test`, `install`, `lint`...).
- Recursão com `$(MAKE) -C subdir`, nunca `make` literal (preserva flags e `-j`).
- Nada de caminho absoluto da máquina: use variáveis (`PREFIX ?= /usr/local`,
  `CURDIR`, `$(HOME)`), com `?=` para o usuário poder sobrescrever.
- Cada linha de receita roda num shell novo: encadeie com `&&` ou use `.ONESHELL:`; para
  falhar cedo, `SHELL := bash` + `.SHELLFLAGS := -eu -o pipefail -c` (ou `set -e` na receita).
- `$` do shell vira `$$` dentro da receita.
- Prefira regras de padrão (`%.o: %.c`) e variáveis automáticas (`$@`, `$<`, `$^`) a
  repetir comandos; gere dependências de header com `-MMD -MP` em vez de listá-las à mão.
- Alvo padrão (`all` ou `help`) primeiro; `clean` só apaga o que o build gera.
- Use `@` só para silenciar eco de comandos triviais; não esconda comandos que falham.
