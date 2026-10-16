# figjam-pm-canvas

Scripts para montar e preencher pôsteres PM Canvas em FigJam via `use_figma`
(MCP do Figma), no layout do template "PM Canvas — Template Residência PNAAT
Cariri" (`figma.com/board/hIxqiUy9gy4QMFNDICXRW8`). Primeiro uso: board
"PM Canvas — Esplendida" (Empresa 08), 2026-09-28.

| arquivo | uso |
|---|---|
| `build-poster.js` | cria N pôsteres (section + grade + tags + textos) e já preenche os stickies. Editar só o bloco ENTRADA. |
| `fill-stickies.js` | preenche stickies num pôster já existente, dado o `SECTION_ID`. |
| `stickies-to-entrada.mjs` | gera o bloco ENTRADA a partir dos `*.stickies.md` de uma empresa e valida palavras e linhas. Saída em `entradas/<empresa>.js`. |
| `cdp/` | Chrome logado via CDP: `chrome-up.sh` (Xvfb + VNC + Chrome), `run-build.mjs` (monta no navegador, sem cota), `measure.mjs` (mede os stickies antes), `eval.mjs`, `input.mjs`, `nav.mjs`, `shot2.mjs` e `png.py` (conferência visual). |
| `write-links.py` | grava os links das sections nos `.md` e o do board no índice, a partir do retorno do build. |

Os dois `.js` são colados direto no parâmetro `code` do `use_figma`: JS puro com
`await` e `return` no topo, sem IIFE.

## De onde vieram as medidas

Tirei print do template via Chrome + CDP (1800×1013, zoom "fit") e medi com
`cdp/png.py`. O script decodifica o PNG e varre transições de cor numa linha ou
coluna. Isso dá o bbox e o hex exatos de cada bloco e tag. As coordenadas
horizontais no script estão em **px de tela, relativos ao canto do pôster**, e
cada uma é multiplicada por `S` para virar unidade de canvas. A altura dos
blocos não vem mais do template (ver "Layout v2").

## Layout v2 (legível sem zoom)

A meta é ler o pôster inteiro enquadrado (fit) num print de 1800 px de largura,
com a fonte do sticky ≥ ~10 px. No fit, o pôster ocupa ~1468×788 px da tela
(o resto é a UI do FigJam). Por isso:

- **`S = 4.1`.** É o menor valor que ainda põe 3 stickies de 240 por linha numa
  coluna de 232 (`3·240 + 2·32 + 2·40 ≤ 232·S`). Benefícios cabe 7 por linha e
  Restrições 15. Com `S = 4.1`, o pôster tem ~5.890 de largura e o fit dá zoom
  ~0,25, ou seja, fonte 40 → ~10 px.
- **Largura enxuta.** A faixa vazia à direita do template (onde ficava o painel
  "Como usar") virou uma coluna estreita que só guarda o sticky de data:
  `POSTER_W = (1087 + 232 + 20)·S + 240 + 39·S`.
- **Fonte 40 fixa** em todo sticky, sem `fitFont`. A 40, o sticky comporta **3
  linhas** (fica com 244 de altura; com 4 linhas vai a 304). A largura útil é
  de ~205 (medido: "tempo real", com 204, cabe; "Tempos por", com 231, não
  cabe). Acima de `MAX_H = 250`, o script **acusa** em `textOverflow`. Uma palavra larga demais
  para uma linha a 40 quebra no meio e sai em `longWords`. O teste é empírico:
  6 linhas da palavra contra 6 de "a". Pela métrica da Inter Medium, isso
  acontece a partir de ~9 letras largas, por exemplo "Manutenção" (238),
  "Distribuição" (228), "Cronograma" (238) e "Porosidade" (217, no limite).
  Troque a palavra ou abrevie. Um item pode ser uma **lista de variantes**
  (`['Defeito nº 1: porosidade', 'Poros: o maior defeito']`): vale a
  primeira sem quebra nem estouro, e o retorno diz qual entrou, em `chosen`.
- **≤ 6 palavras por sticky**, agrupando itens. O pôster é resumo, o `.md`
  continua sendo a fonte completa. O texto condensado fica só no ENTRADA.
- **Altura variável, topologia do template.** São 5 colunas, as mesmas cores,
  Benefícios em 2 colunas e Restrições em 4. Os blocos ficam em 4 faixas
  alinhadas (0: Justificativas/Produto; 1: Objetivos/Requisitos; 2:
  Benefícios/Equipe/Entregas/Linha do tempo; 3: Restrições/Custos). Stakeholders,
  Premissas e Riscos ocupam as faixas 0+1. Cada faixa tem a altura do bloco mais
  cheio: `cabeçalho + linhas·272 − 32 + 24`. Um bloco vazio reserva 1 linha. Se
  um bloco alto pede mais que 0+1, o excesso é dividido entre as duas faixas.
- **Teto de proporção.** A altura do pôster precisa ficar ≤ `largura / ASPECT`
  (`ASPECT = 1.78`); senão, entra `{key: 'poster'}` em `overflow`. Na prática
  isso dá cerca de **6 linhas de stickies somando as 4 faixas** (por exemplo,
  1+2+2+1).
- **Título e linha de registro** em 1 linha: a fonte encolhe até caber.
  A **tag** do bloco se alarga até o rótulo caber, porque o padding interno do
  shape não escala com `S`.
- **Remontagem:** `REMOVE` (lista de ids) apaga sections na mesma chamada.
- **Subtítulo do bloco** com `max(7·S, 40)`, quebrando em até 2 linhas. O
  cabeçalho do bloco cresce junto.

## Convenções

- **Cor do sticky:** paleta FigJam, na cor da coluna. Violeta `#D3BDFF` (Por
  quê?), amarelo `#FFE299` (O quê?), vermelho `#FFB8A8` (Quem?), verde
  `#B3EFBD` (Como?) e azul `#A8DAFF` (Quando e quanto?).
- **Pendente:** o prefixo `§` no texto gera sticky **cinza** `#E6E6E6`, para
  itens "a preencher".
- **Chaves dos blocos:** `just obj ben prod req stk eq prem ent restr risk lt
  cust`.
- **Grid dentro do bloco:**
  - `PAD 40` de margem.
  - `SG 32` entre stickies.
  - Cabeçalho = tag + subtítulo medido.
  - `cols = floor((w − 2·PAD + SG) / (240 + SG))`.
- **Localização dos blocos:** cada bloco é um `ShapeWithText` com o nome igual
  ao rótulo ("Requisitos"). É assim que o `fill-stickies.js` encontra o bloco.
- **`fill-stickies.js`** só preenche. Ele não cresce o bloco e acusa `overflow`
  quando não cabe. Para crescer, remonte o pôster com `build-poster.js`.
- **`RENAME`** (no `build-poster.js`) renomeia sections antigas na mesma
  chamada, por exemplo `(v1)`, sem apagar nada.
- **Painel "Como usar":** fica fora das cópias. O rótulo duplicado de
  Restrições, que existe no template, está corrigido.

## Limites

- **Sticky:** o STICKY do FigJam é 240×240 fixo (ou 416 no modo largo) e não
  aceita `resize()`. Se o texto transborda, ele cresce na altura. Por isso a
  grade é que escala, não o sticky.
- **Cota:** o MCP do Figma no plano Free/Starter tem cota baixa de chamadas.
  Use **1 chamada para todos os pôsteres** da empresa. O retorno traz
  `overflow`, `textOverflow`, `longWords`, largura, altura e proporção. Se tudo
  vier vazio, dispensa uma chamada de verificação.
- **Posição:** o `build-poster.js` coloca os pôsteres novos à direita do
  conteúdo que já existe na página.
- **v1 × v2:** os boards da Esplendida e da Juá ainda estão no layout v1
  (`S = 7.2`, fonte 40→16, altura do template).

## Conferência pelo Chrome (WSLg + CDP)

O print headless não funciona: o CloudFront devolve 403 para o UA
HeadlessChrome, o board pede login e o WebGL vem bloqueado. Use um Chrome com
interface gráfica e perfil isolado:

```bash
google-chrome --remote-debugging-port=9222 --user-data-dir=$CLAUDE_JOB_DIR/tmp/chrome-profile \
  --no-first-run --ignore-gpu-blocklist --use-angle=swiftshader --enable-unsafe-swiftshader "<url do board>"
# usuário loga uma vez na janela
node --experimental-websocket cdp/nav.mjs <fileKey> "<url>?node-id=3-2"   # navega; Figma dá zoom no nó
node --experimental-websocket cdp/shot2.mjs out.png <fileKey> 1           # print da aba cujo URL contém fileKey
python3 -c "import sys; sys.path.insert(0,'cdp'); from png import *; im=load('out.png'); print(px(im,100,100))"
```

- **Zoom:** navegar para `?node-id=<id do sticky>` dá zoom de leitura. O
  `clip.scale > 1` do CDP só amplia o bitmap e não deixa o texto mais nítido.
- **OAuth do MCP:** a mesma janela logada serve para abrir a URL de autorização.
  O usuário só precisa clicar em "Allow".

Ver no vault: `Print de Board Figma Logado via Chrome WSLg + CDP` e
`Reconstruir Template FigJam via use_figma a partir de Medidas de Print`.
