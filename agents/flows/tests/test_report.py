"""Testes do `engine.report` (T8) com o CLI falso: sem rede e sem cota."""

import json

import pytest

from engine import cli, report
from tests.test_cli import CliEnv


@pytest.fixture
def cenv(tmp_path, capsys):
    return CliEnv(tmp_path, capsys)


def usage_reply(fake, agent_id, *rows):
    """Põe cabeçalhos com uso no transcript do filho falso: um por resposta."""
    state = fake._load()
    state["agents"][agent_id]["replies"] = [
        f"{text}" for text in state["agents"][agent_id]["replies"]
    ]
    state["agents"][agent_id]["headers"] = list(rows)
    fake._save(state)


def run_two_phases(cenv):
    cenv.flow(cenv.node("a"), cenv.node("b", ["out/a.md"], when="sensitive"))
    cenv.fake.queue(cenv.done("a"))
    code, out, _ = cenv.main("run", cenv.flow_path.as_posix(), "--slug", "demo")
    assert code == 0
    run_id = next(cenv.state_dir.glob("demo-*.json")).stem
    cenv.main("status", "--run", run_id)
    return run_id


def rep(cenv, run_id, *extra):
    return cenv.main("report", run_id, *extra)


def test_report_lists_phase_model_duration_result_and_output(cenv):
    run_id = run_two_phases(cenv)
    code, out, err = rep(cenv, run_id, "--json")
    assert code == 0, err
    rows = {r["node"]: r for r in json.loads(out)["phases"]}
    assert rows["a"]["result"] == "done"
    assert rows["a"]["requested_model"] == "sonnet"
    assert rows["a"]["applied_model"] == "sonnet"
    assert rows["a"]["diverged"] is False
    assert rows["a"]["outputs"] == ["out/a.md"]
    assert rows["a"]["duration_s"] is not None
    assert rows["a"]["interventions"] == 0
    assert rows["a"]["quota"] == {
        "before": {"five_hour": 10, "seven_day": 20, "updated_at": 1234},
        "after": {"five_hour": 10, "seven_day": 20, "updated_at": 1234},
    }
    assert rows["b"]["quota"] is None  # pulado: nunca leu a cota


def test_report_table_shows_the_quota_before_and_after_each_phase(cenv):
    run_id = run_two_phases(cenv)
    _, out, _ = rep(cenv, run_id)
    lines = {line.split()[0]: line for line in out.splitlines()[2:]}
    assert "5h 10→10 7d 20→20" in lines["a"]
    assert "n/d" in lines["b"]
    assert "5h 10→10" not in lines["b"]


def test_report_table_marks_a_missing_quota_reading_as_nd(cenv):
    run_id = run_two_phases(cenv)
    path = next(cenv.state_dir.glob("demo-*.json"))
    state = json.loads(path.read_text())
    state["nodes"]["a"]["quota_after"] = {"five_hour": None, "seven_day": None, "updated_at": None}
    state["nodes"]["a"]["quota_before"] = {"five_hour": 36, "seven_day": 61, "updated_at": 1}
    path.write_text(json.dumps(state))
    _, out, _ = rep(cenv, run_id)
    assert "5h 36→n/d 7d 61→n/d" in out


def test_report_reads_a_state_saved_before_the_quota_fields_existed(cenv):
    run_id = run_two_phases(cenv)
    path = next(cenv.state_dir.glob("demo-*.json"))
    state = json.loads(path.read_text())
    for ns in state["nodes"].values():
        ns.pop("quota_before", None)
        ns.pop("quota_after", None)
    path.write_text(json.dumps(state))
    code, out, err = rep(cenv, run_id, "--json")
    assert code == 0, err
    assert all(r["quota"] is None for r in json.loads(out)["phases"])


def test_report_flags_model_divergence(cenv):
    cenv.fake.update(apply_model={"sonnet": "haiku"})
    run_id = run_two_phases(cenv)
    _, out, _ = rep(cenv, run_id, "--json")
    row = next(r for r in json.loads(out)["phases"] if r["node"] == "a")
    assert (row["requested_model"], row["applied_model"], row["diverged"]) == ("sonnet", "haiku", True)
    _, text, _ = rep(cenv, run_id)
    assert "sonnet" in text and "haiku" in text and "DIVERGE" in text


def test_report_skipped_node_is_shown_as_skipped(cenv):
    run_id = run_two_phases(cenv)
    _, out, _ = rep(cenv, run_id, "--json")
    row = next(r for r in json.loads(out)["phases"] if r["node"] == "b")
    assert row["result"] == "skipped"
    assert row["duration_s"] is None
    _, text, _ = rep(cenv, run_id)
    assert "skipped" in text


def test_transcript_without_usage_gives_nd_context(cenv):
    run_id = run_two_phases(cenv)
    _, out, _ = rep(cenv, run_id, "--json")
    row = next(r for r in json.loads(out)["phases"] if r["node"] == "a")
    assert row["context_end"] is None and row["context_peak"] is None
    _, text, _ = rep(cenv, run_id)
    assert "n/d" in text


def test_context_end_and_peak_come_from_assistant_rows_with_usage(cenv):
    run_id = run_two_phases(cenv)
    child = next(iter(cenv.fake.agents))
    state = cenv.fake._load()
    state["agents"][child]["messages"] = ["briefing", "ajuste"]
    state["agents"][child]["replies"] = ["r1", "r2"]
    state["agents"][child]["headers"] = [
        "input_tokens=10 | cache_read_input_tokens=1000 | cache_creation_input_tokens=100",
        "input_tokens=5 | cache_read_input_tokens=400 | cache_creation_input_tokens=50",
    ]
    cenv.fake._save(state)
    _, out, _ = rep(cenv, run_id, "--json")
    row = next(r for r in json.loads(out)["phases"] if r["node"] == "a")
    assert row["context_peak"] == 1110
    assert row["context_end"] == 455
    assert row["interventions"] == 1


def test_missing_run_fails_with_a_short_message(cenv):
    code, out, err = rep(cenv, "nao-existe")
    assert code != 0 and out == ""
    assert "nao-existe" in err and len(err.splitlines()) == 1


def test_report_never_prints_secrets(cenv):
    run_id = run_two_phases(cenv)
    _, text, _ = rep(cenv, run_id)
    assert "TRAYCER" not in text and "/home/x" not in text
