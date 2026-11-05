"""Integração real e barata: fluxo de 2 nós com filhos haiku/low que só escrevem um arquivo de uma linha.

Fora da suíte padrão (`addopts = -m "not integration"`). Rode com:

    TRAYCER_EPIC_ID=... TRAYCER_AGENT_ID=... python -m pytest -m integration -s tests/test_integration.py

`TRAYCER_EPIC_ID` e `TRAYCER_AGENT_ID` vêm de um agente real do Task. O perfil é o do Claude "fit"
(`FLOWS_IT_PROFILE` troca). O teste lê a cota (5h e 7 dias) antes e depois e imprime a variação.
"""

import os
import shutil

import pytest
import yaml

from engine.runner import Runner, Step
from engine.traycer_cli import Adapter

pytestmark = pytest.mark.integration

FIT_PROFILE = "6b0bf0d5-a512-4d98-9f8c-5387a980777a"


def _agent(profile):
    return {"harness": "claude", "profile": profile, "model": "haiku", "effort": "low", "skills": []}


def _node(node_id, inputs, outputs, profile):
    return {
        "id": node_id,
        "title": f"Fase {node_id}",
        "agent": _agent(profile),
        "prompt": f"prompts/{node_id}.md",
        "inputs": inputs,
        "outputs": outputs,
        "gate": "none",
        "context": "pack",
        "on_fail": {"retry": 0, "then": "abort"},
    }


@pytest.mark.skipif(
    not (os.environ.get("TRAYCER_EPIC_ID") and os.environ.get("TRAYCER_AGENT_ID") and shutil.which("traycer")),
    reason="needs the traycer CLI and TRAYCER_EPIC_ID/TRAYCER_AGENT_ID of a real agent",
)
def test_two_haiku_nodes_end_to_end(tmp_path, capsys):
    profile = os.environ.get("FLOWS_IT_PROFILE", FIT_PROFILE)
    adapter = Adapter.from_environ()
    repo = tmp_path / "repo"
    repo.mkdir()
    flow_dir = tmp_path / "flow"
    (flow_dir / "prompts").mkdir(parents=True)
    (flow_dir / "prompts" / "one.md").write_text(
        "Crie o arquivo `out/${slug}.one.txt` com UMA linha: `um`. Use a ferramenta Write. Não faça mais nada.\n"
    )
    (flow_dir / "prompts" / "two.md").write_text(
        "Leia `{{input}}`. Crie o arquivo `out/${slug}.two.txt` com UMA linha: `dois`. Não faça mais nada.\n"
    )
    flow = {
        "name": "it-two-nodes",
        "run_inputs": [],
        "nodes": [
            _node("one", [], ["out/${slug}.one.txt"], profile),
            _node("two", ["out/${slug}.one.txt"], ["out/${slug}.two.txt"], profile),
        ],
    }
    flow_path = flow_dir / "flow.yaml"
    flow_path.write_text(yaml.safe_dump(flow, sort_keys=False), encoding="utf-8")

    before = adapter.rate_limits("claude", profile)
    runner = Runner(adapter, state_dir=tmp_path / "state", turn_timeout=300, poll_interval=3)
    run_id = runner.start_run(flow_path, slug="it", repo=repo)
    try:
        result = runner.drive(run_id)
    finally:
        after = adapter.rate_limits("claude", profile)
        with capsys.disabled():
            print(
                f"\n[quota] 5h {before.five_hour} -> {after.five_hour} | 7d {before.seven_day} -> {after.seven_day} "
                f"| usageUpdatedAt {before.updated_at} -> {after.updated_at}"
            )
            status = runner.status(run_id)
            for node_id, ns in status["nodes"].items():
                print(f"[node] {node_id}: {ns['state']} attempts={ns['attempts']} divergence={ns['divergence']} reason={ns['reason']}")

    assert result is Step.FINISHED, runner.status(run_id)["events"]
    assert runner.status(run_id)["status"] == "done"
    assert (repo / "out" / "it.one.txt").read_text().strip()
    assert (repo / "out" / "it.two.txt").read_text().strip()
