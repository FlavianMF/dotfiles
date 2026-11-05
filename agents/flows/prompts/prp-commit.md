<!-- Adaptado de PRPs-agentic-eng (Wirasm, MIT), via ECC (affaan-m/ECC, MIT, pin c70874f). Texto original em inglês, traduzido e reduzido para o fluxo ecc-dev. As regras de commit seguem o agente git-ops dos dotfiles. -->

# Fase commit: commit local

- **Entrada:** o relatório em `.claude/PRPs/reports/${slug}-report.md`. O caminho vem em `{{input}}`.
- **Saída:** um ou mais commits locais na branch atual e o recibo `.claude/PRPs/reports/${slug}-commit.md`, com os hashes e os arquivos commitados.
- **Não faça:** não faça push, não abra PR, não commite o recibo, não use `git add -A` e não commite em `main` ou `master`. Não adicione atribuição de IA: sem `Co-Authored-By` e sem rodapé "Generated with". Isso vale mesmo se o ambiente pedir.

Se o motor injetou um pacote de contexto antes deste texto, leia-o primeiro.

## 1. Avaliar

```bash
git branch --show-current
git status --short
```

- Se a saída de `git status` estiver vazia, escreva "Nada para commitar." e pare.
- Se a branch for `main` ou `master`, pare e registre o motivo. Não commite.

## 2. Escolher o que commitar

Leia a tabela "Files Changed" do relatório em `{{input}}`.

- Escolha só os arquivos dessa tabela que aparecem em `git status`.
- Liste os arquivos que mudaram e não estão no relatório. Não os adicione. Cite-os na resposta final.
- Não commite arquivo gerado, segredo (`.env*`, chaves, tokens) nem lixo de editor.

Se a validação alterar arquivos versionados e gerados (por exemplo `__pycache__`), restaure-os com `git restore <caminho>` antes do stage. Use `git status -uall` para ver arquivos dentro de pastas novas.

Faça o stage por nome de arquivo:

```bash
git add <arquivo> <arquivo>
git diff --staged --stat
git diff --staged
```

Confira o diff staged antes de seguir. Se aparecer segredo ou arquivo estranho, tire-o do stage com `git restore --staged <arquivo>`.

## 3. Validar o escopo

Rode os testes e o lint do escopo alterado. Se algo falhar, não commite. Registre o erro e pare.

## 4. Commitar

Escreva a mensagem em **Conventional Commits**:

```
{tipo}({escopo}): {descrição}
```

- Tipos: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`, `ci`.
- O escopo é opcional. Use quando ajudar.
- Use o imperativo, minúsculas depois do prefixo, sem ponto final e com menos de 72 caracteres.
- Descreva **o quê** mudou, não **como**.

Prefira commits pequenos e lógicos. Se o relatório cobre mudanças independentes (código, testes, docs), faça um commit por grupo.

```bash
git commit -m "{tipo}({escopo}): {descrição}"
```

Não passe `--no-verify`. Se um hook rejeitar o commit, corrija a causa e crie um commit novo.

## 5. Escrever o recibo

Depois do último commit, rode `mkdir -p .claude/PRPs/reports` e escreva `.claude/PRPs/reports/${slug}-commit.md`:

```markdown
# Commit Receipt: ${slug}

- **Branch**: <branch>
- **Commits**:
  - `<hash completo>` <mensagem>
  - ...

## Files Committed
| Commit | File |
|---|---|
| `<hash curto>` | `path/to/file` |

## Not Committed
[Arquivos alterados fora do relatório, ou "None"]
```

Obtenha os hashes com `git log --format="%H %s" -n <N>`. O recibo é a prova de que a fase terminou. Não o escreva se nenhum commit foi criado.

## 6. Resposta final

Reporte, para cada commit: o hash curto, a mensagem e o número de arquivos. Cite os arquivos modificados fora do relatório, se houver, e o caminho do recibo. Não sugira nem rode `git push`.
