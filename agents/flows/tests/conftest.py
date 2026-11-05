import copy
import os
from pathlib import Path

import pytest
import yaml

FLOWS_DIR = Path(__file__).resolve().parent.parent
ECC_DEV = FLOWS_DIR / "flows" / "ecc-dev.yaml"


def make_node(node_id, inputs=(), outputs=(), **overrides):
    node = {
        "id": node_id,
        "title": f"Node {node_id}",
        "agent": {
            "harness": "claude",
            "profile": "ambient",
            "model": "sonnet",
            "effort": "medium",
            "skills": [],
        },
        "prompt": f"prompts/{node_id}.md",
        "inputs": list(inputs),
        "outputs": list(outputs),
        "gate": "none",
        "context": "pack",
        "on_fail": {"retry": 1, "then": "ask_before_upgrade"},
    }
    node.update(overrides)
    return node


@pytest.fixture
def node():
    return make_node


@pytest.fixture
def flow_data():
    """Fluxo válido de 3 nós: a -> b e a -> c, com uma entrada do run. b é condicional."""
    return {
        "name": "demo",
        "run_inputs": ["notes/${slug}.idea.md"],
        "nodes": [
            make_node("a", ["notes/${slug}.idea.md"], ["out/${slug}.a.md"], mode="manual", gate="human"),
            make_node("b", ["out/${slug}.a.md"], ["out/${slug}.b.md"], when="diff_lines > 150 or sensitive"),
            make_node("c", ["out/${slug}.a.md"], ["out/${slug}.c.md"]),  # b é condicional: ninguém consome a saída dele
        ],
    }


@pytest.fixture
def write_flow(tmp_path):
    def _write(data):
        path = tmp_path / "flow.yaml"
        path.write_text(yaml.safe_dump(copy.deepcopy(data), sort_keys=False), encoding="utf-8")
        # O validador exige que o prompt exista: cada nó válido ganha um arquivo vazio.
        nodes = data.get("nodes") if isinstance(data, dict) else None
        for raw in nodes if isinstance(nodes, list) else ():
            prompt = raw.get("prompt") if isinstance(raw, dict) else None
            if isinstance(prompt, str) and prompt.strip() and not os.path.isabs(prompt):
                target = Path(os.path.normpath(os.path.join(tmp_path, prompt)))
                if target.is_relative_to(tmp_path.parent):
                    try:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.touch()
                    except (OSError, ValueError):
                        pass  # prompt inválido de propósito: o loader reporta o erro
        return path

    return _write
