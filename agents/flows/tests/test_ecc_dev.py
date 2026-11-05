from pathlib import Path

import pytest

from engine.loader import load_flow

from conftest import ECC_DEV, FLOWS_DIR


def test_ecc_dev_loads_with_six_phases():
    flow = load_flow(ECC_DEV, slug="demo")
    assert [n.id for n in flow.nodes] == ["prd", "plan", "implement", "review", "commit", "pr"]
    by_id = {n.id: n for n in flow.nodes}
    assert by_id["prd"].mode == "manual" and by_id["prd"].gate == "human"
    assert all(n.mode == "auto" for n in flow.nodes if n.id != "prd")
    assert by_id["plan"].agent.model == "sonnet" and by_id["plan"].agent.effort == "medium"
    assert by_id["plan"].outputs == (".claude/PRPs/plans/demo.plan.md",)
    assert by_id["plan"].inputs == (".claude/PRPs/prds/demo.prd.md",)
    assert by_id["implement"].gate == "none" and by_id["implement"].agent.effort == "high"
    assert by_id["review"].agent.harness == "claude"
    assert by_id["review"].agent.model == "opus" and by_id["review"].agent.effort == "high"
    assert by_id["review"].gate == "human"
    assert by_id["review"].when == "diff_lines > 150 or sensitive"
    assert by_id["commit"].agent.model == "haiku" and by_id["commit"].gate == "none"
    assert by_id["pr"].gate == "human"
    for n in flow.nodes:
        assert Path(n.prompt) == FLOWS_DIR / "prompts" / f"prp-{n.id}.md"


def test_ecc_dev_passes_graph_validation():
    # load_flow valida o grafo por padrão: levanta FlowError se houver ciclo, órfã ou duplicata.
    load_flow(ECC_DEV, slug="demo")


def test_ecc_dev_execution_order_is_declaration_order():
    from engine.validate import execution_order

    flow = load_flow(ECC_DEV, slug="demo")
    assert [n.id for n in execution_order(flow)] == ["prd", "plan", "implement", "review", "commit", "pr"]


def test_commit_runs_after_review():
    flow = load_flow(ECC_DEV, slug="demo")
    assert flow.node("commit").after == ("review",)
    assert all(n.after == () for n in flow.nodes if n.id != "commit")


def test_every_node_uses_the_claude_profile():
    flow = load_flow(ECC_DEV, slug="demo")
    assert {n.agent.profile for n in flow.nodes} == {"6b0bf0d5-a512-4d98-9f8c-5387a980777a"}
