import copy
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
        return path

    return _write
