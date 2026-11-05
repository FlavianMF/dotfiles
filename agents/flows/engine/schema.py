"""Schema do fluxo: tipos imutáveis que T3 e T4 consomem, enums e erro comum.

Contrato com T3/T4:

    from engine.loader import load_flow
    flow: Flow = load_flow(path, slug="minha-feature")   # já validado, ${slug} resolvido
    from engine.validate import execution_order
    for node in execution_order(flow): ...                # ordem topológica estável

Cada `Node` traz `inputs`/`outputs` relativos à raiz do repo, sem `${slug}`. `Node.prompt` é
absoluto (resolvido a partir do diretório do YAML), então não depende do cwd.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

MODES = ("auto", "manual")
GATES = ("none", "human")
CONTEXTS = ("pack", "fork")
ON_FAIL_THEN = ("ask_before_upgrade", "abort")
HARNESSES = ("claude", "antigravity", "opencode", "codex")
EFFORTS = ("low", "medium", "high")

NODE_ID_RE = re.compile(r"^[a-z][a-z0-9_-]{0,63}$")
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

# Campos do nó: obrigatórios e opcionais (com o padrão aplicado pelo loader).
REQUIRED_NODE_FIELDS = ("id", "title", "agent", "prompt", "inputs", "outputs", "gate", "context", "on_fail")
OPTIONAL_NODE_FIELDS = {"mode": "auto", "when": None, "after": ()}
REQUIRED_AGENT_FIELDS = ("harness", "profile", "model", "effort")
OPTIONAL_AGENT_FIELDS = {"skills": ()}
REQUIRED_ON_FAIL_FIELDS = ("retry", "then")
FLOW_FIELDS = ("name", "run_inputs", "nodes")


class FlowError(Exception):
    """Fluxo inválido. `errors` lista cada problema; toda mensagem cita o nó."""

    def __init__(self, errors: Sequence[str] | str) -> None:
        self.errors = [errors] if isinstance(errors, str) else list(errors)
        super().__init__("\n".join(self.errors))


@dataclass(frozen=True)
class AgentSpec:
    harness: str
    profile: str
    model: str
    effort: str
    skills: tuple[str, ...] = ()


@dataclass(frozen=True)
class OnFail:
    retry: int
    then: str


@dataclass(frozen=True)
class Node:
    id: str
    title: str
    mode: str  # auto | manual
    agent: AgentSpec
    prompt: str  # caminho absoluto, resolvido a partir do diretório do YAML
    inputs: tuple[str, ...]  # caminhos já resolvidos
    outputs: tuple[str, ...]  # caminhos já resolvidos
    gate: str  # none | human
    when: str | None  # expressão validada por engine.when; None = sempre roda
    context: str  # pack | fork
    on_fail: OnFail
    # ids que rodam antes deste nó, sem produzir saída que ele consuma (ordem explícita).
    # Um nó em `after` que foi pulado (`when` falso) conta como satisfeito.
    after: tuple[str, ...] = ()


@dataclass(frozen=True)
class Flow:
    name: str
    slug: str
    source: Path  # caminho absoluto do YAML de origem
    run_inputs: tuple[str, ...]  # caminhos que o run fornece (resolvidos)
    nodes: tuple[Node, ...]  # na ordem de declaração do YAML

    def node(self, node_id: str) -> Node:
        for n in self.nodes:
            if n.id == node_id:
                return n
        raise KeyError(node_id)
