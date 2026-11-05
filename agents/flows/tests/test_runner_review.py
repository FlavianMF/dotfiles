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
