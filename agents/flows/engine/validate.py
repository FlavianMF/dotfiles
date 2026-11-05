"""Checagens de grafo do fluxo (já com `${slug}` resolvido) e o CLI `flow-validate`.

Regras: ids únicos; toda entrada é saída de outro nó ou está em `run_inputs`;
nenhuma saída aparece em dois nós; nenhuma entrada depende só de nó condicional (`when`);
`after` cita ids existentes; sem ciclo (as arestas de `after` contam). Os erros citam o nó e o campo.

    python3 -m engine.validate flows/ecc-dev.yaml [--slug SLUG]
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict

from engine.schema import Flow, FlowError, Node

DEFAULT_SLUG = "example"


def _producers(flow: Flow) -> dict[str, list[int]]:
    producers: dict[str, list[int]] = defaultdict(list)
    for i, node in enumerate(flow.nodes):
        for path in node.outputs:
            producers[path].append(i)
    return producers


def _edges(flow: Flow) -> dict[int, set[int]]:
    """Aresta produtor -> consumidor, por índice, mais as arestas `after` (um laço é um ciclo)."""
    producers = _producers(flow)
    by_id: dict[str, list[int]] = defaultdict(list)
    for i, node in enumerate(flow.nodes):
        by_id[node.id].append(i)
    edges: dict[int, set[int]] = {i: set() for i in range(len(flow.nodes))}
    for j, node in enumerate(flow.nodes):
        for node_id in node.after:
            for i in by_id.get(node_id, ()):
                edges[i].add(j)
    for j, node in enumerate(flow.nodes):
        for path in node.inputs:
            for i in producers.get(path, ()):
                edges[i].add(j)
    return edges


def _find_cycles(flow: Flow, edges: dict[int, set[int]]) -> list[list[int]]:
    cycles: list[list[int]] = []
    state: dict[int, int] = {}  # 1 = no caminho atual, 2 = concluído
    path: list[int] = []

    def visit(i: int) -> None:
        state[i] = 1
        path.append(i)
        for j in sorted(edges[i]):
            if state.get(j) == 1:
                cycles.append(path[path.index(j):] + [j])
            elif j not in state:
                visit(j)
        path.pop()
        state[i] = 2

    for i in range(len(flow.nodes)):
        if i not in state:
            visit(i)
    return cycles


def _cycle_errors(flow: Flow, edges: dict[int, set[int]]) -> list[str]:
    errors = []
    for cycle in _find_cycles(flow, edges):
        ids = [flow.nodes[i].id for i in cycle]
        errors.append(
            f"node '{ids[0]}': field 'inputs/after': cycle {' -> '.join(repr(i) for i in ids)}"
        )
    return errors


def check_flow(flow: Flow) -> list[str]:
    """Devolve todos os erros de grafo; lista vazia significa fluxo válido."""
    errors: list[str] = []
    seen_ids: set[str] = set()
    for node in flow.nodes:
        if node.id in seen_ids:
            errors.append(f"node '{node.id}': field 'id': duplicate node id")
        seen_ids.add(node.id)

    producers = _producers(flow)
    for path, indexes in producers.items():
        if len(indexes) > 1:
            owners = ", ".join(f"node '{flow.nodes[i].id}'" for i in indexes)
            first = flow.nodes[indexes[0]].id
            errors.append(f"node '{first}': field 'outputs': '{path}' is produced more than once ({owners})")

    for node in flow.nodes:
        for node_id in node.after:
            if node_id not in seen_ids:
                errors.append(f"node '{node.id}': field 'after': unknown node id '{node_id}'")

    declared = set(flow.run_inputs)
    for path in sorted(declared & producers.keys()):
        owner = flow.nodes[producers[path][0]].id
        errors.append(f"node '{owner}': field 'outputs': '{path}' is also declared in run_inputs")
    for node in flow.nodes:
        for path in node.inputs:
            if path not in producers and path not in declared:
                errors.append(
                    f"node '{node.id}': field 'inputs': '{path}' is not an output of any node "
                    "nor declared in run_inputs"
                )
            elif path in producers and all(flow.nodes[i].when is not None for i in producers[path]):
                skipped = ", ".join(f"node '{flow.nodes[i].id}'" for i in producers[path])
                errors.append(
                    f"node '{node.id}': field 'inputs': '{path}' is produced only by conditional "
                    f"{skipped} (when), which may be skipped; node '{node.id}' would lose its input"
                )

    errors.extend(_cycle_errors(flow, _edges(flow)))
    return errors


def validate_flow(flow: Flow) -> None:
    errors = check_flow(flow)
    if errors:
        raise FlowError(errors)


def execution_order(flow: Flow) -> list[Node]:
    """Ordem topológica; entre nós prontos, vence a ordem de declaração. Levanta FlowError em ciclo."""
    edges = _edges(flow)
    cycle_errors = _cycle_errors(flow, edges)
    if cycle_errors:
        raise FlowError(cycle_errors)
    pending = {i: 0 for i in range(len(flow.nodes))}
    for targets in edges.values():
        for j in targets:
            pending[j] += 1
    order: list[Node] = []
    ready = sorted(i for i, n in pending.items() if n == 0)
    while ready:
        i = ready.pop(0)
        order.append(flow.nodes[i])
        for j in sorted(edges[i]):
            pending[j] -= 1
            if pending[j] == 0:
                ready.append(j)
        ready.sort()
    return order


def main(argv: list[str] | None = None) -> int:
    from engine.loader import load_flow

    parser = argparse.ArgumentParser(prog="engine.validate", description="Valida um YAML de fluxo.")
    parser.add_argument("flow", help="caminho do YAML do fluxo")
    parser.add_argument("--slug", default=DEFAULT_SLUG, help=f"slug de teste (padrão: {DEFAULT_SLUG})")
    args = parser.parse_args(argv)
    try:
        flow = load_flow(args.flow, slug=args.slug)
        order = execution_order(flow)
    except FlowError as exc:
        for error in exc.errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"OK {args.flow}: {len(flow.nodes)} nodes ({' -> '.join(n.id for n in order)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
