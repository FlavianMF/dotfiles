"""Achados da revisão a frio (commit 7c91766): um teste por achado, escrito antes da correção."""

import json
import os
import subprocess
from pathlib import Path

import pytest

from engine.run_state import RunStore, StateError
from engine.runner import RunError, Runner, Step
from tests.test_runner import Env


@pytest.fixture
def env(tmp_path):
    return Env(tmp_path)


# 1. `_fail` tentava failed -> failed quando a repetição falha ao criar o filho ----------------


def test_create_failing_on_every_retry_reaches_awaiting_upgrade(env):
    env.flow(env.node("a", on_fail={"retry": 2, "then": "ask_before_upgrade"}))
    env.fake.update(fail={"create": "sem vaga"})
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    node = env.runner.status(run_id)["nodes"]["a"]
    assert node["state"] == "awaiting_upgrade"
    assert node["attempts"] == 3
    assert env.history(run_id, "a") == ["running", "failed", "running", "failed", "running", "failed", "awaiting_upgrade"]


def test_unreadable_prompt_on_a_retry_also_ends_in_awaiting_upgrade(env):
    env.flow(env.node("a", on_fail={"retry": 1, "then": "ask_before_upgrade"}))
    env.fake.queue({"write": {}})
    run_id = env.start()
    env.runner.step(run_id)  # 1ª tentativa roda e termina sem saída
    prompt = env.tmp_path / "prompts" / "a.md"
    prompt.chmod(0)  # a repetição não consegue ler o prompt
    try:
        assert env.drive(run_id) is Step.BLOCKED
    finally:
        prompt.chmod(0o644)
    assert env.states(run_id) == {"a": "awaiting_upgrade"}
    assert env.history(run_id, "a") == ["running", "failed", "running", "failed", "awaiting_upgrade"]


# 2. abort_run não pode depender do YAML --------------------------------------------------------


@pytest.mark.parametrize("damage", ["remove", "change_nodes", "invalid"])
def test_abort_run_works_when_the_flow_file_is_gone_or_changed(env, damage):
    env.flow(env.node("a"), env.node("b", ["out/a.md"]))
    env.fake.queue({"active_polls": 100})
    run_id = env.start()
    env.runner.step(run_id)
    if damage == "remove":
        env.flow_path.unlink()
    elif damage == "change_nodes":
        env.flow(env.node("zzz"))
    else:
        env.flow_path.write_text("nodes: [")
    env.runner.abort_run(run_id)
    status = env.runner.status(run_id)
    assert status["status"] == "aborted"
    assert env.states(run_id) == {"a": "aborted", "b": "aborted"}
    (agent,) = env.fake.agents.values()
    assert agent["archived"] and len(env.fake.commands("stop")) == 1
    env.flow(env.node("a"))
    env.start()  # o repo ficou livre


# 3. `_refresh_manual` ignorava predecessores e `when` -------------------------------------------


def test_approve_gate_refuses_a_manual_node_whose_predecessor_is_still_running(env):
    env.flow(env.node("a", gate="human"), env.node("prd", ["out/a.md"], mode="manual", gate="human"))
    env.fake.queue({"active_polls": 100})  # `a` fica rodando
    run_id = env.start()
    env.runner.step(run_id)
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("arquivo velho\n")  # saída de um run anterior
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")
    assert env.states(run_id) == {"a": "running", "prd": "pending"}


def test_approve_gate_refuses_a_manual_node_whose_when_was_not_evaluated(env):
    env.flow(env.node("prd", mode="manual", gate="human", when="sensitive"))
    run_id = env.start()  # nenhum step: o `when` ainda não foi avaliado
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("arquivo velho\n")
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")
    assert env.states(run_id) == {"prd": "pending"}


def test_approve_gate_refuses_a_manual_node_that_the_when_skips(env):
    env.flow(env.node("prd", mode="manual", gate="human", when="sensitive"))
    run_id = env.start(sensitive=False)
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("arquivo velho\n")
    env.drive(run_id)
    assert env.states(run_id) == {"prd": "skipped"}
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")


def test_approve_gate_still_refreshes_a_ready_manual_node(env):
    env.flow(env.node("prd", mode="manual", gate="human", when="sensitive"))
    run_id = env.start(sensitive=True)
    env.drive(run_id)  # `when` avaliado, arquivo ainda não existe
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("prd\n")
    env.runner.approve_gate(run_id, "prd")  # o arquivo apareceu entre dois steps
    assert env.states(run_id) == {"prd": "done"}
