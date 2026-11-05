<!-- Adaptado de PRPs-agentic-eng (Wirasm, MIT), via ECC (affaan-m/ECC, MIT, pin c70874f). Texto original em inglês, traduzido e reduzido para o fluxo ecc-dev. -->

# Fase plan: plano de implementação

- **Entrada:** o PRD em `.claude/PRPs/prds/${slug}.prd.md`. O caminho vem em `{{input}}`.
- **Saída:** `.claude/PRPs/plans/${slug}.plan.md`. Use o mesmo `${slug}` do PRD.
- **Não faça:** não escreva código de produção, não rode migrações, não commite e não implemente nenhuma tarefa do plano.

Se o motor injetou um pacote de contexto antes deste texto, leia-o primeiro.

Crie um plano detalhado e autocontido. Ele captura os padrões, as convenções e o contexto do código para implementar a funcionalidade de uma só vez.

**Regra de ouro:** se você precisaria buscar no código durante a implementação, registre esse conhecimento agora, no plano.

## Escopo

Planeje só o que o `{{input}}` pede. Se o PRD tem mais fases, planeje só a fase escolhida na seção 0. Escreva as outras fases, e qualquer extra que ninguém pediu (CI, release, scripts de versão), em "NOT Building". Não planeje o que o PRD lista para depois.

## 0. Detectar a entrada

| Entrada em `{{input}}` | Ação |
|---|---|
| Caminho terminado em `.prd.md` | Leia o PRD e ache a próxima fase elegível |
| `.md` com "Implementation Phases" | Trate como PRD |
| Outro arquivo | Leia como contexto livre |
| Texto livre | Trate como descrição da funcionalidade |
| Vazio | Registre o erro em uma frase e pare. Não invente a funcionalidade |

Se a entrada for um PRD:

1. Leia a seção **Implementation Phases**.
2. Escolha a próxima fase `pending` cujas dependências estejam `complete`.
3. Extraia nome, descrição, critérios, dependências e restrições da fase.
4. Use a descrição da fase como a funcionalidade a planejar.

Se nenhuma fase estiver `pending`, escreva isso no relatório final e pare.

## 1. Entender

Identifique **o quê** (entrega concreta), **por quê** (valor), **quem** usa e **onde** isso entra no código.

Escreva a user story:

```
Como [tipo de usuário],
quero [capacidade],
para que [benefício].
```

Estime a complexidade:

| Nível | Indícios | Escopo típico |
|---|---|---|
| Small | Um arquivo, mudança isolada | 1-3 arquivos, <100 linhas |
| Medium | Vários arquivos, segue padrões existentes | 3-10 arquivos, 100-500 linhas |
| Large | Mudança transversal, padrões novos, integrações | 10+ arquivos, 500+ linhas |
| XL | Mudança de arquitetura ou migração | 20+ arquivos, considere dividir |

**Portão de ambiguidade:** esta fase roda sem o usuário na conversa. Se a entrega principal for vaga, os critérios de sucesso faltarem ou houver várias interpretações válidas, não chute. Liste as perguntas no topo do plano, em "Notes", e escreva o plano com a interpretação mais conservadora, marcada como suposição. O usuário revisa o plano antes de seguir.

## 2. Explorar o código

Busque diretamente, com `grep`, `find` e leitura, em 8 categorias:

1. **Implementações parecidas:** funcionalidades análogas.
2. **Convenções de nome:** arquivos, funções, variáveis, classes, exports.
3. **Tratamento de erro:** como erros são capturados, propagados e devolvidos.
4. **Logs:** o que se registra, em que nível e formato.
5. **Tipos:** tipos, interfaces e schemas relevantes.
6. **Padrões de teste:** onde ficam, nomes, setup e estilo de asserção.
7. **Configuração:** arquivos, variáveis de ambiente, flags.
8. **Dependências:** pacotes e módulos internos usados por código parecido.

Depois trace 5 pontos: pontos de entrada, fluxo de dados, mudanças de estado, contratos que precisam ser respeitados e padrões de arquitetura.

Compile tudo em uma tabela:

| Categoria | Arquivo:linhas | Padrão | Trecho |
|---|---|---|---|

Se o projeto não tem type-check ou lint, escreva "N/A" nos comandos de validação e use o validador mais próximo. Se não existe código real para um padrão (por exemplo logs), escreva "N/A: sem exemplo no repositório". Não invente trechos.

Se o PRD deixa um "TBD" que nenhuma pesquisa resolve (decisão de produto), liste-o em "Notes" e adote a suposição conservadora, marcada como suposição.

## 3. Pesquisar

Se a funcionalidade usa bibliotecas, APIs ou tecnologia desconhecidas, consulte a documentação oficial. Registre cada achado assim:

```
KEY_INSIGHT: [o que aprendeu]
APPLIES_TO: [qual parte do plano afeta]
GOTCHA: [avisos ou armadilhas de versão]
```

Se só usa padrões internos já conhecidos, escreva: "Sem pesquisa externa: usa padrões internos estabelecidos."

## 4. Desenhar a experiência

Se houver mudança visível ao usuário, descreva o antes e o depois e a tabela de interações. Se for mudança interna, escreva: "Mudança interna: sem transformação de UX."

## 5. Arquitetar

Defina a abordagem, as alternativas consideradas e rejeitadas, o escopo concreto e a lista explícita do que **não** será construído.

## 6. Gerar

Rode `mkdir -p .claude/PRPs/plans` e escreva `.claude/PRPs/plans/${slug}.plan.md` com este modelo:

````markdown
# Plan: [Nome da funcionalidade]

## Summary
[2-3 frases]

## User Story
Como [usuário], quero [capacidade], para que [benefício].

## Problem → Solution
[Estado atual] → [Estado desejado]

## Metadata
- **Complexity**: [Small | Medium | Large | XL]
- **Source PRD**: [caminho ou "N/A"]
- **PRD Phase**: [nome da fase ou "N/A"]
- **Estimated Files**: [número]

---

## UX Design
### Before
[diagrama ASCII ou "N/A: mudança interna"]
### After
[diagrama ASCII ou "N/A: mudança interna"]
### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|

---

## Mandatory Reading
Arquivos que o implementador DEVE ler antes:

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 (critical) | `path/to/file` | 1-50 | Padrão principal |
| P1 (important) | `path/to/file` | 10-30 | Tipos relacionados |
| P2 (reference) | `path/to/file` | all | Implementação parecida |

## External Documentation
| Topic | Source | Key Takeaway |
|---|---|---|

---

## Patterns to Mirror
Padrões reais do código. Siga-os exatamente.

### NAMING_CONVENTION
// SOURCE: [arquivo:linhas]
[trecho real]

### ERROR_HANDLING
// SOURCE: [arquivo:linhas]
[trecho real]

### LOGGING_PATTERN
// SOURCE: [arquivo:linhas]
[trecho real]

### TEST_STRUCTURE
// SOURCE: [arquivo:linhas]
[trecho real]

(Acrescente REPOSITORY_PATTERN, SERVICE_PATTERN etc. quando existirem.)

---

## Files to Change
| File | Action | Justification |
|---|---|---|
| `path/to/file` | CREATE | motivo |
| `path/to/existing` | UPDATE | motivo |

## NOT Building
- [Item fora de escopo]

---

## Step-by-Step Tasks

### Task 1: [Nome]
- **ACTION**: [o que fazer]
- **IMPLEMENT**: [código ou lógica específica]
- **MIRROR**: [padrão de "Patterns to Mirror" a seguir]
- **IMPORTS**: [imports necessários]
- **GOTCHA**: [armadilha a evitar]
- **VALIDATE**: [como verificar a tarefa]

(Repita para todas as tarefas.)

---

## Testing Strategy

### Unit Tests
| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|

### Edge Cases Checklist
- [ ] Entrada vazia
- [ ] Entrada de tamanho máximo
- [ ] Tipos inválidos
- [ ] Acesso concorrente
- [ ] Falha de rede (se aplicável)
- [ ] Permissão negada

---

## Validation Commands

### Static Analysis
```bash
[comando de type-check do projeto]
```
EXPECT: zero erros de tipo

### Unit Tests
```bash
[comando de teste da área afetada]
```
EXPECT: todos passam

### Full Test Suite
```bash
[comando da suíte completa]
```
EXPECT: sem regressões

### Manual Validation
- [ ] [checklist de verificação manual]

---

## Acceptance Criteria
- [ ] Todas as tarefas concluídas
- [ ] Todos os comandos de validação passam
- [ ] Testes escritos e passando
- [ ] Sem erros de tipo nem de lint

## Completion Checklist
- [ ] Código segue os padrões descobertos
- [ ] Erros e logs seguem o estilo do código
- [ ] Testes seguem os padrões de teste
- [ ] Sem valores fixos no código
- [ ] Sem escopo extra
- [ ] Autocontido: nenhuma pergunta necessária na implementação

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|

## Notes
[Decisões, suposições e perguntas em aberto]
````

## 7. Saída

1. Salve o plano em `.claude/PRPs/plans/${slug}.plan.md`.
2. Se a entrada foi um PRD, mude a fase escolhida de `pending` para `in-progress` e preencha a coluna "PRP Plan" com o caminho do plano.
3. Reporte: o arquivo, o PRD de origem, a fase, a complexidade, o número de arquivos e tarefas, os 3 principais padrões, a pesquisa externa, o maior risco e uma nota de confiança de 1 a 10 para implementar de uma só vez.

## Verificação antes de terminar

- **Contexto completo:** os arquivos relevantes, as convenções, os padrões de erro e de teste, e as dependências estão no plano.
- **Pronto para implementar:** cada tarefa tem ACTION, IMPLEMENT, MIRROR e VALIDATE. Nenhuma tarefa exige nova busca no código. Os imports estão listados.
- **Fiel aos padrões:** os trechos são reais, os `SOURCE` apontam para arquivo e linha existentes.
- **Validação coberta:** há comandos de análise estática, de teste e de build.
- **Teste de quem não conhece o código:** uma pessoa nova no repositório implementa só com este plano. Se não der, acrescente o contexto que falta.
