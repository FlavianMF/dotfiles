<!-- Adaptado de PRPs-agentic-eng (Wirasm, MIT), via ECC (affaan-m/ECC, MIT, pin c70874f). Texto original em inglês, traduzido e reduzido para o fluxo ecc-dev. -->

# Fase implement: executar o plano

- **Entrada:** o plano em `.claude/PRPs/plans/${slug}.plan.md`. O caminho vem em `{{input}}`.
- **Saída:** o código do plano, nos arquivos que ele lista, e o relatório `.claude/PRPs/reports/${slug}-report.md`.
- **Não faça:** não commite, não faça push, não abra PR e não mude o escopo do plano. Não mova nem apague o plano. Não enfraqueça um teste para ele passar.

Se o motor injetou um pacote de contexto antes deste texto, leia-o primeiro.

Execute o plano passo a passo e valide cada mudança na hora. Não acumule estado quebrado.

**Regra de ouro:** se uma validação falhar, corrija antes de seguir.

## Escopo

Implemente só o escopo do `{{input}}`: as tarefas do plano e os arquivos de "Files to Change". Se o PRD de origem tem mais fases, não implemente nenhuma delas. Se uma tarefa pedir um arquivo fora dessa lista, pare e registre o motivo no relatório em vez de criar o arquivo.

## 0. Detectar o projeto

Ache o gerenciador de pacotes e os scripts de validação (type-check, lint, teste, build):

| Arquivo | Ferramenta |
|---|---|
| `bun.lockb` | bun |
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |
| `pyproject.toml` ou `requirements.txt` | uv ou pip |
| `Cargo.toml` | cargo |
| `go.mod` | go |
| `Makefile` | alvos do `make` |

Prefira os comandos que o próprio plano lista em "Validation Commands".

## 1. Carregar o plano

Leia o arquivo de `{{input}}`. Extraia: Summary, Patterns to Mirror, Files to Change, Step-by-Step Tasks, Validation Commands e Acceptance Criteria.

Se o arquivo não existir ou não for um plano válido, escreva o erro em uma frase e pare. Não crie o relatório.

## 2. Preparar o git

```bash
git branch --show-current
git status --porcelain -- . ':!.claude/PRPs'
```

Ignore `.claude/PRPs/`: ali ficam o PRD, o plano e os relatórios do fluxo. Eles não contam como árvore suja.

| Estado | Ação |
|---|---|
| Em branch de funcionalidade | Use a branch atual |
| Em `main` ou `master`, árvore limpa | Crie `git checkout -b feat/${slug}` |
| Em `main` ou `master`, árvore suja | Pare e registre o motivo. Não mexa nas mudanças existentes |
| Em worktree desta funcionalidade | Use o worktree |

Nunca commite aqui. Nunca rode `git pull`, `git push` nem `git stash`.

## 3. Executar as tarefas

Para cada tarefa de **Step-by-Step Tasks**, em ordem:

1. **Leia o MIRROR.** Abra o arquivo do padrão citado e entenda a convenção antes de escrever.
2. **Implemente.** Siga o padrão, aplique os GOTCHA e use os IMPORTS indicados.
3. **Valide na hora.** Depois de cada mudança de arquivo, rode o type-check. Se falhar, corrija antes do próximo arquivo.
4. **Registre.** Anote `Task N: [nome] - completa`.

Se precisar desviar do plano, anote **o quê** mudou e **por quê**. Esses desvios entram no relatório.

## 4. Validar

Rode todos os níveis do plano. Corrija cada nível antes do seguinte.

1. **Análise estática:** type-check com zero erros, lint com auto-fix e correção manual do que sobrar.
2. **Testes unitários:** escreva testes para cada função nova e cubra os casos de borda do plano. Se um teste falhar, corrija a implementação, não o teste, a menos que o teste esteja errado.
3. **Build:** deve passar sem erros.
4. **Integração (se aplicável):** suba o servidor, espere ele responder, rode os testes e encerre o servidor. Dê timeout de 30 segundos para a subida.
5. **Casos de borda:** percorra a checklist de "Testing Strategy".

Se a validação alterar arquivos versionados e gerados (por exemplo `__pycache__`), restaure-os com `git checkout -- <caminho>`. Se o projeto não tiver type-check, lint ou build, escreva N/A no relatório e use o validador mais próximo (por exemplo `python3 -m py_compile`).

Os testes são o portão desta fase. Só escreva o relatório com todos os níveis verdes.

## 5. Relatório

Rode `mkdir -p .claude/PRPs/reports` e escreva `.claude/PRPs/reports/${slug}-report.md`:

```markdown
# Implementation Report: [Nome da funcionalidade]

## Summary
[O que foi implementado]

## Assessment vs Reality
| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | [do plano] | [real] |
| Confidence | [do plano] | [real] |
| Files Changed | [do plano] | [contagem real] |

## Tasks Completed
| # | Task | Status | Notes |
|---|---|---|---|
| 1 | [nome] | Complete | |
| 2 | [nome] | Complete | Desvio: [motivo] |

## Validation Results
| Level | Status | Notes |
|---|---|---|
| Static Analysis | Pass | |
| Unit Tests | Pass | N testes escritos |
| Build | Pass | |
| Integration | Pass | ou N/A |
| Edge Cases | Pass | |

## Files Changed
| File | Action | Lines |
|---|---|---|
| `path/to/file` | CREATED | +N |
| `path/to/file` | UPDATED | +N / -M |

## Deviations from Plan
[Desvios com O QUÊ e POR QUÊ, ou "None"]

## Issues Encountered
[Problemas e como foram resolvidos, ou "None"]

## Tests Written
| Test File | Tests | Coverage |
|---|---|---|
| `path/to/test` | N | [área coberta] |
```

A tabela "Files Changed" deve listar todo arquivo criado ou alterado. A fase `commit` usa essa lista para escolher o que commitar.

Se o plano veio de um PRD, mude a fase de `in-progress` para `complete` e acrescente o caminho do relatório.

## 6. Resposta final

Reporte: o caminho do plano, a branch, o resumo da validação (type-check, lint, testes, build, integração), o número de arquivos criados e alterados, os desvios e o caminho do relatório.

## Se algo falhar

- **Type-check:** leia o erro, corrija o arquivo de origem, rode de novo e siga só com saída limpa.
- **Teste:** descubra se o erro está na implementação ou no teste. Corrija a causa raiz e rode de novo.
- **Lint:** rode o auto-fix, corrija o resto à mão e rode de novo.
- **Build:** em geral é tipo ou import. Corrija o arquivo indicado e rode de novo.
- **Integração:** confira se o servidor subiu, se a rota existe e se o formato da requisição bate.

## Critérios de sucesso

- Todas as tarefas do plano executadas.
- Zero erros de tipo e de lint.
- Testes verdes, com testes novos escritos.
- Build passa.
- Relatório salvo em `.claude/PRPs/reports/${slug}-report.md`.
