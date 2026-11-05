# Harness² — Recursive Agent Harnessing

Componente do dotfiles para gerenciamento, instalação e integração do **Harness²** ([Google Research](https://github.com/google-research/harness2), arXiv: 2610.14224), um framework para harnessing recursivo de agentes em mundo aberto.

## O que é o Harness²?

Um **harness** é o sistema ao redor de um modelo de linguagem que permite sua atuação como agente autônomo: prompts de sistema, ferramentas, memória, skills, regras e orquestração. **Harnessing** é o processo sistemático de otimização desse ambiente.

O Harness² conecta dois níveis de recursão mantendo os pesos dos modelos fixos:

1. **Recursão no nível da tarefa (Task-level recursion)**: Refina o harness de execução para a tarefa atual através do ciclo contrastivo **Propose–Probe–Compose**:
   - *Propose*: propõe invariantes e edições específicas ao domínio.
   - *Probe*: testa os efeitos na mesma tarefa sem feedback de ground-truth.
   - *Compose*: compõe um harness refinado a partir dos contrastes comportamentais observados entre execuções.
2. **Recursão no nível de melhoria (Harnessing-level recursion)**: Um *Experience Reflector* atualiza um harness persistente de melhoria com harnesses adotados e lições comprovadas por evidências para guiar tarefas futuras.

## Estrutura e Localização

- **Repositório**: `~/projetos_harness/harness2` (override via `HARNESS2_HOME`).
- **Ambiente virtual**: `~/projetos_harness/harness2/.venv` (Python 3.12+ gerenciado via `uv`).
- **Executáveis** (vinculados em `~/.local/bin/`):
  - `harness2`: CLI principal para executar sweeps de adaptação em benchmarks.
  - `harness2-setup`: Configuração e download de dependências dos benchmarks (`jb`, `wb`, `lab`).
  - `harness2-check`: Validador de ambiente, modelos configurados e requisitos.
  - `harness2-demo`: Demonstração rápida de uma rodada de adaptação local.
  - `harness2-judge`: Avaliação e pontuação de trajetórias contra rubricas dos benchmarks.
  - `harness2-report`: Geração de relatórios comparativos entre baseline e versões recursivas.
  - `harness2-bridge`: Ponte para a API Responses do Codex e contêineres de execução.

## Instalação

Pelo instalador do dotfiles:

```bash
./install.sh --with=harness2
```

Ou diretamente via Makefile:

```bash
make harness2-install
```

Para atualizar o repositório e dependências:

```bash
make harness2-update
```

Para validar a instalação:

```bash
make harness2-check
```

## Configuração

Copie o template de segredos para o diretório de segredos do dotfiles:

```bash
cp secrets/harness2.env.example secrets/harness2.env
```

O arquivo `secrets/harness2.env` é carregado automaticamente pelo `~/.zshrc` em cada sessão do terminal.

### Variáveis principais

| Variável | Descrição | Exemplo |
| :--- | :--- | :--- |
| `GOOGLE_CLOUD_PROJECT` | ID do projeto no Google Cloud (Vertex AI) | `meu-projeto-gcp` |
| `GOOGLE_CLOUD_LOCATION` | Região do Vertex AI | `global` ou `us-central1` |
| `HARNESS2_SOLVER_MODEL` | Modelo executor (sintaxe do OpenCode) | `google/gemini-2.5-flash` |
| `HARNESS2_JUDGE_MODEL` | Modelo avaliador (bare model ID) | `gemini-2.5-pro` |
| `HARNESS2_IMPROVER_MODEL`| Modelo que propõe edições de harness | `gemini-2.5-pro` |
| `HARNESS2_RUNS_DIR` | Diretório raiz para armazenar os rollouts | `~/projetos_harness/harness2/runs` |

## Integração com Traycer

O repositório em `~/projetos_harness/harness2` suporta canais customizados de proposição via `--proposer-channel`:

```bash
harness2 --bench jb --k 1 --mode parallel \
  --proposer-channel traycer \
  --proposer-model "antigravity:gemini-3.8-flash"
```

O canal `traycer` utiliza o harness e a orquestração do Traycer para propor mutações e síntese do harness.

## Aliases do Shell (zsh/harness2.zsh)

- `harness2-cd`: Navega diretamente para a pasta do Harness² (`~/projetos_harness/harness2`).
- `harness2-venv`: Ativa o ambiente virtual do Harness² na sessão atual do shell.
