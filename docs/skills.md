# Skills por projeto

Skills soltas pesam em todo turno quando ficam em `~/.claude/skills`. Este dotfiles mantém essas skills fora do escopo global e liga cada uma só onde o projeto precisa dela.

Para a medição do custo, leia [[context total esconde a economia da lista de skills]] e [[Medição de Tokens do Setup - Baseline Estático e Contexto Longo]]. Para o lugar desta camada no router, leia [[Router de Tokens em 3 Camadas - Carga, Contexto e Modelo]]. `agents/AGENTS.md` traz a regra para as skills de design.

## Como funciona

O script `claude/skills-project.sh` lê `claude/skills-auto.conf`. Cada linha tem o formato `skill=tipos`. O tipo do projeto vem de `claude/ecc-detect.sh` e pode ser `web`, `node`, `c` ou `none`.

As skills moram em `~/.agents/skills`. O script cria links em `<raiz do git>/.claude/skills/<skill>` que apontam para lá.

O script tem três comandos:

| Comando | Efeito |
| --- | --- |
| `auto [dir]` | Liga as skills do tipo do projeto. Apaga os links que ele mesmo criou e que o tipo não pede mais. |
| `status [dir]` | Mostra o que o `auto` gerencia no projeto. |
| `add <skill> [dir]` | Liga uma skill avulsa, mesmo do tipo `manual`. |

O `auto` anota cada link que criou em `.claude/skills.auto`. Ele nunca apaga uma skill que o projeto já tinha. Ele também grava os links no `.git/info/exclude`, então o `git status` não os lista. O estado só vale em sessão nova.

O `auto` não faz nada neste repositório. Ele também não faz nada em projeto com o arquivo `.claude/skills.off`.

## Skills do tipo `manual`

O `auto` nunca liga uma skill `manual`. Para ligar uma, rode:

```bash
claude/skills-project.sh add <skill> [dir]
```

O `add` falha com código 1 se a skill não existir em `~/.agents/skills`. Se o link já existir, ele só avisa. O `auto` também não apaga um link que o `add` criou.

Em 2026-11-12, `claude/skills-auto.conf` listava 23 skills:

- 14 skills de design ligam em projeto `web`.
- `ecc-security-review`, `verification-loop`, `search-first` e `eval-harness` ligam em projeto `web`, `node` e `c`.
- `figjam-pm-canvas`, `reverse-engineer-anything`, `llm-council`, `find-skills` e `full-output-enforcement` são `manual`.

## Peças ligadas ao script

- `zsh/ecc-auto.zsh` chama `skills-project.sh auto` antes de abrir o `claude`. A variável `SKILLS_AUTO=0` desliga a chamada. A chamada tem limite de 5 segundos.
- O `install.sh` pula as skills do `skills-auto.conf` ao criar links globais. Isso vale para as skills do pacote ECC e para as duplicadas por plugin. As skills continuam em `~/.agents/skills`.
- O `Makefile` inclui o script no lint.
- O teste `tests/skills_project_test.sh` cobre o tipo `manual` e o comando `add`. O teste e o `shellcheck -S warning` passaram em 2026-11-12.

## Efeito medido no conjunto global

Duas specs do épico registram o corte. O número exato de links globais depende da máquina.

- Em "Corte de tokens do bloco de skills" (2026-11-12), o conjunto global em `~/.claude/skills` caiu de 60 links para 14. O bloco injetado em todo turno pesava cerca de 10,9 mil tokens. A conta é uma estimativa de caracteres divididos por 4.
- Em "Skills avulsas em escopo de projeto" (2026-11-12), nove skills saíram do conjunto global. Quatro ligam por tipo e cinco são `manual`.
- Em 2026-11-12, `~/.claude/skills` desta máquina tinha 5 entradas: 3 links e os diretórios `learned` e `synced`. O total bate com 14 menos 9. Eu não reproduzi a contagem de 60 links, pois falta o estado anterior.
- A conta da primeira spec não fecha sozinha. Ela diz que saíram 35 duplicados de plugin e 14 de design. A conta dá 11 links, não 14. A lista `PLUGIN_DUPLICATE_SKILLS` do `install.sh` confirma os 35 duplicados. O `skills-auto.conf` confirma os 14 de design.

## Pendências registradas

- Mover `mattpocock-skills` e `typesafe` para o modo por projeto em `claude/plugins-auto.conf`. Hoje esse arquivo lista só `figma`, `playwright` e `impeccable`. A spec também pedia o `playwright`, e ele já está lá.
- O `claude/settings.json` mantém o plugin `figma` ligado no escopo de usuário. O `plugins-project.sh auto` grava `false` nos projetos que não são `web`. Ele não faz nada neste repositório. A spec "Corte de tokens do bloco de skills" diz que o `figma` pesa nas sessões do Traycer. Não verifiquei essa parte.
- Medir o ganho real com `/context` numa sessão nova.
- Rodar `install.sh` e confirmar que nenhum link global volta.

## Fontes

- Spec "Corte de tokens do bloco de skills" (artifact do épico, 2026-11-12).
- Spec "Skills avulsas em escopo de projeto" (artifact do épico, 2026-11-12).
- `claude/skills-project.sh`, `claude/skills-auto.conf`, `claude/plugins-auto.conf`, `zsh/ecc-auto.zsh`, `install.sh` e `tests/skills_project_test.sh`.
