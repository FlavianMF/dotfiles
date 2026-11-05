"""Contrato entre ecc-dev.yaml e os prompts: cada nó aponta para um prompt que cita seus caminhos."""

import re
from pathlib import Path

import pytest

from engine.loader import load_flow

from conftest import ECC_DEV

SLUG = "demo"
FLOW = load_flow(ECC_DEV, slug=SLUG)
NODES = {n.id: n for n in FLOW.nodes}


def _block(text: str, label: str) -> str:
    """Devolve o bullet `- **<label>:** ...` do cabeçalho do prompt, até o próximo bullet de cabeçalho."""
    match = re.search(
        rf"^- \*\*{label}:\*\*(.*?)(?=^- \*\*|^\s*$)", text, re.MULTILINE | re.DOTALL
    )
    assert match, f"bloco '{label}' ausente no prompt"
    return match.group(1)


def _mentions(block: str, path: str) -> bool:
    """O caminho aparece no bloco, com o slug resolvido ou como placeholder `${slug}`."""
    return path in block or path.replace(SLUG, "${slug}") in block


@pytest.mark.parametrize("node_id", list(NODES))
def test_prompt_file_exists(node_id):
    prompt = Path(NODES[node_id].prompt)
    assert prompt.parent.name == "prompts"
    assert prompt.is_file(), f"prompt do nó '{node_id}' não existe: {prompt}"


@pytest.mark.parametrize("node_id", [i for i, n in NODES.items() if n.mode != "manual"])
@pytest.mark.parametrize("kind", ["inputs", "outputs"])
def test_prompt_blocks_cite_node_paths(node_id, kind):
    node = NODES[node_id]
    text = Path(node.prompt).read_text(encoding="utf-8")
    block = _block(text, "Entrada" if kind == "inputs" else "Saída")
    for path in getattr(node, kind):
        assert _mentions(block, path), f"nó '{node_id}': {kind[:-1]} '{path}' ausente do bloco"
