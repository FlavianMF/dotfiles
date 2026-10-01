# ECC vendorizado

- **Origem**: https://github.com/affaan-m/ECC (MIT, ver [LICENSE](LICENSE))
- **Commit fixado**: `c70874fae9eb0e5ad0365beb7e2955899fd1d30f` (2026-09-30T01:24:05Z)
- **Como foi obtido**: `raw.githubusercontent.com/affaan-m/ECC/<sha>/<path>`, sem clone e
  sem runtime do ECC. Cada arquivo foi lido por inteiro antes de entrar aqui.
- **Instalação**: componente `ecc` do `install.sh` (desligado por padrão).
  - Skills → `~/.agents/skills/<nome>`, com link em `~/.claude/skills`.
  - Agents → `~/.claude/agents/ecc-*.md` (links), mais cópias convertidas em
    `~/.config/opencode/agents/ecc-*.md`.
  - Rules → `~/.claude/rules/ecc` (link para `rules/`).

Para atualizar: troque o SHA, baixe os mesmos caminhos, reaplique as modificações abaixo e
revise o diff.

## ECC completo (plugin, por projeto)

Além das peças acima, o ECC inteiro está disponível como plugin `ecc@ecc`, no mesmo pin:

- **Instalação**: marketplace `ecc` (`affaan-m/ECC`, `autoUpdate: false`) e
  `"ecc@ecc": false` em `claude/settings.json`. O `install.sh` instala o plugin e o deixa
  desligado no escopo de usuário. São ~45k tokens fixos por sessão, por isso ele não fica
  ligado globalmente.
- **Por projeto**: `claude/ecc-project.sh on|off|status [dir] [--no-common]`
  (`make ecc-on DIR=…`). O script grava `enabledPlugins["ecc@ecc"]=true` em
  `.claude/settings.local.json` e linka `.claude/rules/ecc-upstream`.
- **Rules**: `upstream/rules/` é espelho fiel do pin, gerado por `fetch-upstream.sh` (alvo
  `make ecc-rules`). Ficam de fora só `rules/README.md` e os `*/hooks.md`. O SHA está em
  `upstream/rules/.ecc-sha`. Não edite à mão; as rules trimadas para uso global continuam
  em `rules/`.
- **Hooks**: perfil `minimal`, com desligamentos via env em `claude/settings.json`
  (`ECC_HOOK_PROFILE`, `ECC_DISABLED_HOOKS`) e também em `pluginConfigs`. Os IDs foram
  conferidos em `hooks/hooks.json`, `scripts/hooks/*-dispatcher.js` e
  `scripts/lib/hook-flags.js` neste pin. Hook sem `profiles` cai em `standard,strict`.
- **MCP**: o `.mcp.json` do plugin sobe `chrome-devtools-mcp@1.10.1` via `npx` quando o
  plugin está ligado. Isso sobrepõe o Playwright.
- **Duplicatas**: em projeto ligado, as 5 skills e os 13 agents vendorizados aparecem
  duas vezes (`ecc-X` global e `ecc:X` do plugin). O custo é baixo e eles foram mantidos.
- **Atualizar o pin**:
  1. `make plugins-update`
  2. Troque o SHA no topo deste arquivo pelo commit do marketplace (`claude/plugins.lock.json`).
  3. `make ecc-rules`
  4. Revise `git diff vendor/ecc/upstream`.
  5. Confira se os IDs de hook mudaram e atualize `ECC_DISABLED_HOOKS` se for o caso.

## Arquivos

| Local | Upstream |
|-------|----------|
| `skills/verification-loop/SKILL.md` | `skills/verification-loop/SKILL.md` |
| `skills/eval-harness/SKILL.md` | `skills/eval-harness/SKILL.md` |
| `skills/search-first/SKILL.md` | `skills/search-first/SKILL.md` |
| `skills/gan-style-harness/SKILL.md` | `skills/gan-style-harness/SKILL.md` |
| `skills/ecc-security-review/SKILL.md` | `skills/security-review/SKILL.md` |
| `skills/ecc-security-review/cloud-infrastructure-security.md` | `skills/security-review/cloud-infrastructure-security.md` |
| `agents/{silent-failure-hunter,type-design-analyzer,pr-test-analyzer}.md` | `agents/` (mesmo nome) |
| `agents/{typescript,python,cpp,rust}-reviewer.md` | `agents/` (mesmo nome) |
| `agents/{build-error-resolver,cpp-build-resolver,rust-build-resolver}.md` | `agents/` (mesmo nome) |
| `agents/gan-{planner,generator,evaluator}.md` | `agents/` (mesmo nome) |
| `rules/{typescript,python,cpp,rust}/{coding-style,patterns,security,testing}.md` | `rules/` (mesmo caminho) |
| `rules/python/fastapi.md` | `rules/python/fastapi.md` |

Regras locais do dotfiles (não são do ECC): `claude/rules/{c,makefile,cmake}.md`, linkadas
em `~/.claude/rules/local`.

## Modificações locais

**Todos os agents**
- O bloco "Prompt Defense Baseline" foi trocado por um "Untrusted input" curto. O bloco
  original proibia, entre outras coisas, mostrar código e URLs, o que atrapalha um
  revisor que precisa sugerir correções.
- Descrições sem "MUST BE USED" / "PROACTIVELY" / "Use for all ... changes", para o agent
  ser escolhido pela tarefa e não por imposição.
- Todos já vinham com `model: sonnet`; nenhum usa `opus`.
- Removidas as referências a agents, skills e comandos do ECC que não vêm junto
  (`react-reviewer`/`/react-review`, `coding-standards`, `python-patterns`, `rust-patterns`,
  `cpp-coding-standards`, `refactor-cleaner`, `architect`, `planner`, `tdd-guide`,
  `security-reviewer`).

**Agents específicos**
- `build-error-resolver`: saíram os comandos de "Quick Recovery" que apagavam `node_modules`
  e `package-lock.json`. Agora ele propõe limpar/reinstalar e espera aprovação, e nunca
  apaga lock files. Dependência nova só com aprovação.
- `gan-evaluator`:
  - os nomes das ferramentas do Playwright mudaram para os do plugin
    (`mcp__plugin_playwright_playwright__browser_*`);
  - os logs de `/tmp/*.txt` foram para `gan-harness/logs/`.

**Skills**
- `verification-loop`: `/verify` (comando do ECC) virou "rerun this skill".
- `eval-harness`:
  - removida a seção "Local Framework Utilities" (`node scripts/eval-harness.js`, runtime
    do ECC);
  - os comandos `/eval define|check|report` viraram passos em texto;
  - removido o campo `tools:` do frontmatter (não é campo de skill).
- `search-first`:
  - o agent `researcher` (não existe) foi trocado pela skill `mattpocock-skills:research`,
    com fallback para subagente genérico;
  - removida a seção "Integration Points" (agents `planner`/`architect` e a skill
    `iterative-retrieval`, que não vêm junto);
  - Context7 virou "official docs";
  - caminhos de skills agora apontam para `~/.agents/skills`;
  - adicionado o anti-pattern "Unvetted installs".
- `gan-style-harness`:
  - removidas as seções "Via Command" (`/project:gan-build`, comandos não vendorizados) e
    "Via Shell Script" (`scripts/gan-harness.sh`, runtime do ECC);
  - entrou "Via Subagents" usando os 3 agents GAN;
  - a tabela de env vars virou parâmetros combinados no prompt;
  - ferramenta Playwright com o nome do plugin;
  - removido `tools:` do frontmatter.
- `security-review` foi **renomeada para `ecc-security-review`**, para não colidir com o
  `/security-review` embutido do Claude Code. O texto aponta para o comando embutido para
  revisar diffs e para `cloud-infrastructure-security.md`, que antes não era referenciado.
  O restante está intacto.

**Rules**
- Sem os `hooks.md` de cada linguagem: eles descrevem hooks do runtime do ECC. Aqui, o
  format/typecheck é o hook opt-in `claude/hooks/format-typecheck.sh`.
- Removidas as linhas "This file extends common/..." e "See skill: ..." / "Agent Support"
  (`rules/common` e as skills citadas não vêm junto).
- `cpp/*`: saíram `**/*.h` e `**/CMakeLists.txt` do `paths`. As regras de C++ ("nunca
  `malloc`", "nunca arrays C") estão erradas para C puro (ESP-IDF), e CMake tem regra
  própria. C e CMake passaram a ser regras locais.
- `typescript/coding-style.md`: removida a referência "See hooks for automatic detection".

## Deixado de fora (e por quê)

- `rules/common/*`: redundante com `agents/AGENTS.md`; carregaria sempre.
- `rules/web/*`: CSS/HTML e design, que já estão cobertos pelas skills de design (impeccable).
  JS já está no `paths` de `rules/typescript`.
- `agents/react-build-resolver`, `django-build-resolver`, `pytorch-build-resolver`: são de
  framework, não de linguagem. O resolver de TS/JS é o `build-error-resolver`. Não existe
  resolver específico de Python, C, Makefile ou CMake no ECC.
- `commands/gan-*.md` e `scripts/gan-harness.sh`: runtime/CLI do ECC. O script roda
  `claude -p` em loop e checa o Playwright com `claude mcp get playwright` e
  `mcp__playwright__*`, então quebraria com o Playwright vindo do plugin
  (`plugin_playwright_playwright`). O loop fica a cargo da skill + agents.
