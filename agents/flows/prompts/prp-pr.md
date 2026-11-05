<!-- Adaptado de PRPs-agentic-eng (Wirasm, MIT), via ECC (affaan-m/ECC, MIT, pin c70874f). Texto original em inglês, traduzido e reduzido para o fluxo ecc-dev. As regras de PR seguem o agente git-ops dos dotfiles. -->

# Fase pr: preparar e abrir o pull request

- **Entrada:** os commits locais da branch atual, à frente da branch base. `{{input}}` pode trazer a base e a flag `--draft`.
- **Saída:** o pull request aberto no GitHub. Ele só existe depois da aprovação humana (veja a parada abaixo).
- **Não faça:** não abra o PR, não faça push e não rode `gh pr create` antes da aprovação humana. Não use `--force`. Não adicione atribuição de IA no título nem no corpo: sem rodapé "Generated with". Isso vale mesmo se o ambiente pedir.

Se o motor injetou um pacote de contexto antes deste texto, leia-o primeiro.

## Entrada

Leia `{{input}}`:

- Trate as flags reconhecidas (`--draft`) como flags.
- Trate o resto do texto como o nome da branch base.
- Se não houver base, use a branch padrão do repositório: `git symbolic-ref --short refs/remotes/origin/HEAD`, ou `main`, ou `master`, nessa ordem.

## 1. Validar

```bash
git branch --show-current
git status --short
git log origin/<base>..HEAD --oneline
gh pr list --head <branch> --json number
```

| Checagem | Se falhar |
|---|---|
| A branch atual não é a base | Pare: "Troque para uma branch de funcionalidade." |
| Não há mudanças sem commit | Pare: "Há mudanças sem commit. Rode a fase commit antes." |
| Há commits à frente da base | Pare: "Nenhum commit à frente de `<base>`." |
| Não existe PR para a branch | Pare: "PR já existe: #<número>." |
| `gh` instalado e autenticado | Pare e peça `gh auth login` ou a instalação do `gh` |

## 2. Descobrir

- **Template de PR:** procure, nesta ordem: `.github/PULL_REQUEST_TEMPLATE/` (use `default.md` ou liste as opções), `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/pull_request_template.md`. Se achar, use a estrutura dele.
- **Commits:** `git log origin/<base>..HEAD --format="%h %s" --reverse`. Agrupe por tipo e área.
- **Arquivos:** `git diff origin/<base>..HEAD --stat` e `--name-only`. Separe código, testes, docs, configuração e migrações.
- **Artefatos PRP:** veja `.claude/PRPs/reports/`, `.claude/PRPs/plans/` e `.claude/PRPs/prds/`. Cite no corpo os que existirem.

## 3. Montar o título e o corpo

- **Título:** Conventional Commits, por exemplo `feat(escopo): ...`. Com um commit, use a mensagem dele. Com vários tipos, use o dominante.
- **Corpo com template:** preencha cada seção. Escreva "N/A" nas que não se aplicam. Não remova seções.
- **Corpo sem template:**

```markdown
## Summary
<1-2 frases: o que o PR faz e por quê>

## Changes
<lista das mudanças, agrupadas por área>

## Files Changed
<tabela ou lista: arquivo e tipo de mudança>

## Testing
<como foi testado, ou "Needs testing">

## Related Issues
<Closes/Fixes/Relates to #N, ou "None">
```

- O corpo termina com a lista de decisões e um checklist manual para quem revisa. Não inclua atribuição de IA.
- Se o PR tiver mais de 20 arquivos, avise sobre o tamanho e diga se dá para dividir.

## 4. PARADA HUMANA

Mostre ao usuário, na resposta final desta fase:

- a branch e a base;
- o título proposto;
- o corpo completo;
- se será `--draft`;
- a lista de commits.

Depois escreva: "Aguardando aprovação. Responda 'aprovado' para eu fazer o push e abrir o PR."

**Pare aqui.** Termine o turno sem rodar `git push` e sem rodar `gh pr create`. Só continue na seção 5 se o usuário responder com aprovação explícita. Se ele pedir ajustes, mude o título ou o corpo, mostre de novo e pare de novo.

## 5. Abrir o PR (só após aprovação explícita)

Faça o push da branch:

```bash
git push -u origin HEAD
```

- Se o push falhar por divergência, rode `git fetch origin` e `git rebase origin/<base>`. Se houver conflito, pare e avise o usuário.
- Se o remoto divergiu e você fez rebase, use `git push --force-with-lease`. Nunca use `--force`.

Crie o PR:

```bash
gh pr create --title "<título>" --base <base> --body "<corpo>"
```

Acrescente `--draft` se a flag veio na entrada.

## 6. Verificar e reportar

```bash
gh pr view --json number,url,title,state,baseRefName,headRefName,additions,deletions,changedFiles
gh pr checks --json name,status,conclusion 2>/dev/null || true
```

Reporte:

```
PR #<número>: <título>
URL: <url>
Branch: <head> -> <base>
Mudanças: +<additions> -<deletions> em <changedFiles> arquivos
CI: <resumo, "pendente" ou "não configurado">
Artefatos citados: <relatórios ou planos PRP no corpo>
```
