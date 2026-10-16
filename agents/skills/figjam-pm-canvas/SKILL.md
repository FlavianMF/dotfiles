---
name: figjam-pm-canvas
description: Pôster FigJam do PM Canvas a partir de `pm-canvas-empresa-0N*.md`, via `~/.agents/skills/figjam-pm-canvas/tools/`, montado num Chrome logado por CDP (sem cota) ou por `use_figma`. Use ao levar canvas de uma empresa para o board, ao preencher stickies num pôster existente, ou ao conferir o board por print Chrome/CDP.
---

# figjam-pm-canvas

Leva os PM Canvas de uma empresa para um board FigJam: **um arquivo por empresa,
uma section (pôster) por projeto, lado a lado**, no layout do template
`https://www.figma.com/board/hIxqiUy9gy4QMFNDICXRW8`. O template é só leitura:
os pôsteres são reconstruídos por script. Os scripts e as medidas estão em
`~/.agents/skills/figjam-pm-canvas/tools/` (o README explica de onde vêm as medidas e o
"Layout v2").

**Scripts.** Moram na skill, em `~/.agents/skills/figjam-pm-canvas/tools/` (versionados no
dotfiles). Rode os comandos **a partir da raiz do repo da empresa**: os caminhos de `<Pasta>` e
dos `.md` são relativos a ela. Os `entradas/*.js` ficam nessa pasta da skill.

- **v2, o atual:** o pôster é legível enquadrado inteiro (fit) num print de
  1800 px. Todas as empresas estão em v2 (o link de cada board está no índice
  da empresa): IBK, EmbPlast, LFC, HG, IKNET, MaCherrie, Esplendida e Juá.
- **v1, legado:** `S = 7.2`, fonte 40→16 e altura fixa do template. Sobra só
  como sections "(v1)" ao lado dos v2 (Esplendida, MaCherrie) e o layout solto
  antigo da Juá.

## 1. Destilar os stickies

Para cada `pm-canvas-empresa-0N-*.md` de projeto, grave os stickies num
`pm-canvas-empresa-0N-<slug>.stickies.md` ao lado dele. O índice
`pm-canvas-empresa-0N.md`, sem sufixo, não vira pôster, e os `*.stickies.md`
não são canvas. Modelo: `Juá/pm-canvas-empresa-01-energia.stickies.md`, com o
título `# Stickies — ... — Pn: <nome curto>`, um `### <chave>` por bloco e um
`- item` por sticky. Transforme cada `###` do canvas num bloco:

| `###` | chave | `###` | chave |
|---|---|---|---|
| Justificativas | `just` | Equipe | `eq` |
| Objetivos | `obj` | Premissas | `prem` |
| Benefícios | `ben` | Grupos de entregas | `ent` |
| Produto | `prod` | Restrições | `restr` |
| Requisitos | `req` | Riscos | `risk` |
| Stakeholders externos | `stk` | Linha do tempo | `lt` |
| Custos | `cust` | | |

- **Até 6 palavras por sticky, agrupando itens.** O pôster é resumo e o `.md`
  continua completo. O texto condensado fica só no ENTRADA. A fonte é **40
  fixa** num sticky de 240×240, então cabem **3 linhas** de ~9 letras. A
  largura útil é de ~205, e a partir da 4ª linha o sticky cresce para 304. Use
  palavras de até ~9 letras. As mais largas quebram no meio: "Manutenção",
  "Distribuição", "Cronograma", "resfriamento" e "estabilização". Abrevie
  ("Manut.", "Distrib.") ou troque ("Prazos a refinar"). Quando a palavra é
  indispensável, passe variantes separadas por ` || ` (`Defeito nº 1:
  porosidade || Poros: o maior defeito`); vale a primeira que não quebra.
- **Orçamento de linhas.** Os blocos crescem na altura, mas o pôster precisa
  ficar ≤ 16:9 (`ASPECT 1.78`). Isso dá ~6 linhas de stickies somando as 4
  faixas, por exemplo 1+2+2+1:
  - colunas de 232 levam 3 por linha;
  - Benefícios leva 7 e Restrições 15;
  - Stakeholders, Premissas e Riscos levam até ~9 cada.
- **Pendente vira `§`.** Todo campo em branco (`___`), "a definir" ou "a
  confirmar" vira sticky com prefixo `§`, que sai cinza. Os típicos são data da
  visita, alunos alocados, contato na empresa e custos.
- **Canto direito (`date`).** Recebe a data da visita e, na mesma string
  separada por `\n`, o status do canvas quando houver (por exemplo, o
  blockquote "planejado para depois do núcleo"). Esse sticky sai sempre cinza.

**Pronto quando:** cada bullet de cada `###` virou sticky ou foi fundido
de propósito, cada lacuna virou `§` e nenhum sticky passa de 6 palavras.

## 2. Preparar o Chrome e o board

O caminho padrão é montar **no navegador, via CDP**: um FigJam logado expõe a
API de plugins no console da aba (global `figma`), então o `build-poster.js`
roda lá sem MCP e sem cota. O `use_figma` fica de reserva (plano Free, cota
de poucas chamadas).

- **Chrome.** `bash ~/.agents/skills/figjam-pm-canvas/tools/cdp/chrome-up.sh "<url do board>"`
  sobe Xvfb `:99`, x11vnc em `localhost:5900` e Chrome com CDP na porta 9222
  (perfil `~/.cache/figjam-pm-canvas-chrome`), tudo fora da sessão. Rode por
  esse script: tarefa em background morre no limite de tempo e leva o Chrome.
  Headless não serve (403 ou tela de login). No primeiro uso o usuário entra no
  Figma uma vez pelo VNC (`ssh -L 5900:localhost:5900 <host>` e um cliente VNC).
- **Uma aba só.** Máquina com pouca RAM: navegue a mesma aba entre boards
  (`cdp/nav.mjs`). Espere `typeof figma` virar `object` (`cdp/eval.mjs`).
- **Board.** Use o link do campo `**Board FigJam desta empresa (rascunho):**`
  do índice. Se estiver vazio, crie no navegador:
  `curl -X PUT "localhost:9222/json/new?https://www.figma.com/board/new"`,
  pegue o `fileKey` da URL nova e renomeie para `PM Canvas — <Empresa>`
  com duplo clique no título (`cdp/input.mjs <fileKey> dblclick 96 36`,
  `selectall`, `type "<nome>"`, `key Enter`). `figma.root.name` não grava.
- **Pelo MCP (reserva).** Carregue `figma:figma-use` e `figma:figma-use-figjam`,
  passe `skillNames: "figma-use,figma-use-figjam"`, monte todos os pôsteres da
  empresa numa chamada e não gaste chamada com leitura.

## 3. Rodar o script

Gere o bloco ENTRADA a partir dos `.stickies.md`:

```bash
node ~/.agents/skills/figjam-pm-canvas/tools/stickies-to-entrada.mjs <Pasta> [--rename-v1] > ~/.agents/skills/figjam-pm-canvas/tools/entradas/<empresa>.js
```

O conversor sai com erro quando um sticky passa de 6 palavras ou quando um
pôster passa de 6 linhas, que é o teto de 16:9. Ele também avisa quando uma
palavra tem mais de 9 letras e não tem variante. Corrija o `.stickies.md`, nunca
o `.js` gerado. `--rename-v1` renomeia as sections que já estão no board com
" (v1)".

Antes de montar, meça os stickies no navegador. O conversor não sabe a
largura real das letras:

```bash
node --experimental-websocket ~/.agents/skills/figjam-pm-canvas/tools/cdp/measure.mjs <fileKey> <Pasta>/*.stickies.md
```

Ele lista cada sticky com mais de 3 linhas a 40 ou com palavra quebrada no
meio ("Dashboard", "24/09/2026"). Cabem ~10 letras por linha, então 3 linhas
são ~3 palavras curtas. Siga até `0 problemas`. O sticky de data pode passar
de 3 linhas (coluna própria), só não pode quebrar palavra: use `dd/mm/aa`.

Monte pelo navegador:

```bash
node --experimental-websocket ~/.agents/skills/figjam-pm-canvas/tools/cdp/run-build.mjs <fileKey> ~/.agents/skills/figjam-pm-canvas/tools/entradas/<empresa>.js [--remove 3:6,3:524] > ret.json
```

O `run-build.mjs` troca o bloco ENTRADA do `build-poster.js` pela entrada,
traz a aba para a frente (aba em segundo plano é estrangulada e leva minutos)
e imprime o retorno. Pelo MCP, copie o `build-poster.js` inteiro para o
`code`, trocando só o bloco ENTRADA. Os scripts usam `await` e `return` no
topo, então `node --check` acusa erro: é esperado.

Dois cuidados que o script já trata: o sticky sai sem o nome do autor
(`authorVisible = false`; no navegador ele soma 16 de altura) e o teto de 3
linhas (`MAX_H`) é medido na hora, porque o padding do sticky muda entre o
navegador (3 linhas = 240) e o MCP (244).

- **Pôster novo:** `build-poster.js`. Em cada item: `name` = `P1 · <nome curto>`,
  `title` = o `#` do `.md`, `md` = caminho do `.md` relativo à raiz do repo,
  mais `stickies` e `date`. O pôster entra à direita do que já existe na página.
- **Pôster existente:** `fill-stickies.js`, com o `SECTION_ID` no formato da
  API (`3:128`; a URL usa `3-128`). Os stickies novos entram abaixo dos
  existentes. Use `DATE: null` se o pôster já tem o sticky de data, senão o
  script cria outro. Esse script ainda não rodou em produção: na primeira vez,
  confira se `missing` voltou vazio e se `count` bate com o que você mandou.

Mantenha `S = 4.1` em todos os pôsteres do arquivo, para eles ficarem na mesma
escala. A fonte é 40 fixa e não encolhe. A altura de cada faixa segue o bloco
mais cheio, e o bloco vazio reserva 1 linha. Para substituir pôsteres sem
apagar os antigos, use `RENAME` (`{ '1:6': 'P1 · Nome (v1)' }`) na mesma
chamada. Para remontar, use `REMOVE` (lista de ids).

`fill-stickies.js` só preenche: não cresce o bloco e acusa `overflow` quando
não cabe. Para crescer um bloco, remonte o pôster com `build-poster.js`.

**Pronto quando:** o retorno traz `overflow`, `textOverflow` e `longWords`
vazios em todos os pôsteres, `ratio ≥ 1.78`, e você anotou o `sectionId` de
cada um.

- `overflow` com `key: 'poster'`: a proporção passou do teto. Corte stickies
  até sobrar uma linha a menos numa faixa.
- `textOverflow`: o texto passou de 3 linhas a 40 (sticky > `MAX_H`). Encurte
  o sticky.
- `longWords`: a palavra quebra no meio. Troque ou abrevie.

Corrija o `.stickies.md`, gere a entrada de novo e remonte com `--remove` dos
ids antigos. `--rename-v1` renomeia toda section que não termina em "(v1)":
confira antes, com `cdp/eval.mjs`, se o board tem pôsteres em sections ou
blocos soltos de um layout antigo (a Juá tinha), e desfaça o que não for
pôster.

## 4. Conferir pelo print do Chrome

O print sai do mesmo Chrome do passo 2 e não gasta cota. A partir de
`~/.agents/skills/figjam-pm-canvas/tools/`:

```bash
node --experimental-websocket cdp/nav.mjs <fileKey> "<url>?node-id=3-2"   # Figma dá zoom no nó
node --experimental-websocket cdp/shot2.mjs /tmp/p1.png <fileKey> 1       # print da aba do board
```

Para ler texto miúdo, navegue até
`?node-id=<id do sticky>`. O `dsf > 1` só amplia o bitmap e não deixa o texto
mais nítido. Para medir pixel e cor use `cdp/png.py`, com `load(path)` e
`px(img, x, y)`.

**Pronto quando:** você viu cada section enquadrada inteira, com um print por
pôster.

- Todo sticky está dentro do seu bloco, com os pendentes em cinza e a data no
  canto.
- A fonte do sticky fica em ~10 px no print. Meça com `cdp/png.py`: a altura
  da linha de texto, ou a de uma maiúscula, dividida pela razão
  cap-height/fonte da Inter (~0,73).

## 5. Gravar os links nos `.md`

O campo `**Board FigJam desta empresa (rascunho):**` recebe o link de cada
arquivo:

- **Canvas de projeto:** a section do pôster,
  `[P1 no board](https://www.figma.com/board/<fileKey>/<slug>?node-id=3-2)`.
- **Índice:** o board inteiro,
  `[PM Canvas — <Empresa>](https://www.figma.com/board/<fileKey>/<slug>) (N pôsteres P1–PN)`.

`write-links.py` grava tudo a partir do retorno (recusa se houver overflow):

```bash
python3 ~/.agents/skills/figjam-pm-canvas/tools/write-links.py ~/.agents/skills/figjam-pm-canvas/tools/entradas/<empresa>.js ret.json <fileKey> "PM Canvas — <Empresa>"
```

**Pronto quando:** todo `pm-canvas-empresa-0N*.md` da empresa tem o campo
preenchido, e cada `node-id` é o `sectionId` do pôster certo, com `:` trocado
por `-`.
