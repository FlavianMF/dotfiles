"""Testes do servidor FastAPI (T5) com o motor falso: sem rede, sem CLI, sem cota."""

import logging
import re

import pytest
from fastapi.testclient import TestClient

import server.app as server_app
from engine.run_state import LockTimeout
from engine.runner import RepoBusy
from server.app import HOST, create_app
from tests.fake_runner import FakeRunner

PORT = 8765
TOKEN = "t0ken-for-tests-0123456789abcdef"
BASE = f"http://127.0.0.1:{PORT}"


@pytest.fixture
def runner():
    return FakeRunner()


@pytest.fixture
def repo(tmp_path):
    path = tmp_path / "repo"
    path.mkdir()
    return path


@pytest.fixture
def app(runner, repo, flow_data, write_flow):
    return create_app(runner, flow_path=write_flow(flow_data), repo=repo, port=PORT, token=TOKEN, spawn=lambda fn: fn())


@pytest.fixture
def client(app):
    return TestClient(app, base_url=BASE)


@pytest.fixture
def auth():
    return {"X-Flow-Token": TOKEN}


def start(client, auth, slug="feat"):
    response = client.post("/runs", json={"slug": slug}, headers=auth)
    assert response.status_code == 201, response.text
    return response.json()["run_id"]


def node_view(view, node_id):
    return next(n for n in view["nodes"] if n["id"] == node_id)


# --- fluxo feliz ---------------------------------------------------------------------------


def test_page_has_buttons_token_and_no_external_resources(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    page = response.text
    for label in ("Rodar", "Aprovar parada", "Escolher modelo"):
        assert label in page
    assert f'content="{TOKEN}"' in page
    assert "__TOKEN__" not in page and "__NONCE__" not in page
    assert not re.search(r"(src|href)\s*=\s*[\"']?(https?:)?//", page)
    assert response.headers["cache-control"] == "no-store"
    csp = response.headers["content-security-policy"]
    assert "default-src 'none'" in csp and "connect-src 'self'" in csp
    nonce = re.search(r"'nonce-([^']+)'", csp).group(1)
    assert f'nonce="{nonce}"' in page


def test_happy_path_start_gate_approve(client, auth, runner):
    run_id = start(client, auth)
    assert runner.driven == [run_id]  # o servidor põe o motor para andar

    view = client.get(f"/runs/{run_id}").json()
    assert view["run_id"] == run_id and view["status"] == "active"
    assert [n["id"] for n in view["nodes"]] == ["a", "b", "c"]
    a = node_view(view, "a")
    assert a["state"] == "awaiting_gate"
    assert a["actions"] == ["approve"]
    assert a["outputs"] == [{"path": "out/feat.a.md", "exists": False}]
    assert node_view(view, "b")["state"] == "pending"
    assert view["waiting"] == [{"node": "a", "state": "awaiting_gate"}]

    response = client.post(f"/runs/{run_id}/gates/a/approve", headers=auth)
    assert response.status_code == 200
    assert node_view(response.json(), "a")["state"] == "done"
    assert runner.runs[run_id]["nodes"]["a"]["state"] == "done"
    assert runner.driven == [run_id, run_id]  # aprovar religa o motor

    reloaded = client.get(f"/runs/{run_id}").json()  # recarregar a página lê o estado atual
    assert node_view(reloaded, "a")["state"] == "done"
    assert node_view(reloaded, "a")["actions"] == []


def test_output_file_flag_follows_the_repo(client, auth, repo):
    run_id = start(client, auth)
    (repo / "out").mkdir()
    (repo / "out" / "feat.a.md").write_text("plano", encoding="utf-8")
    assert node_view(client.get(f"/runs/{run_id}").json(), "a")["outputs"] == [
        {"path": "out/feat.a.md", "exists": True}
    ]


def test_upgrade_choice(client, auth, runner):
    run_id = start(client, auth)
    runner.force(run_id, "c", "awaiting_upgrade", "retries exhausted")
    assert node_view(client.get(f"/runs/{run_id}").json(), "c")["actions"] == ["upgrade"]

    response = client.post(f"/runs/{run_id}/upgrade", json={"node": "c", "model": "opus", "effort": "high"}, headers=auth)
    assert response.status_code == 200
    ns = runner.runs[run_id]["nodes"]["c"]
    assert ns["state"] == "running" and ns["model"] == "opus" and ns["effort"] == "high"


def test_upgrade_requires_awaiting_upgrade(client, auth, runner):
    run_id = start(client, auth)
    response = client.post(f"/runs/{run_id}/upgrade", json={"node": "a", "model": "opus"}, headers=auth)
    assert response.status_code == 409
    assert "not awaiting_upgrade" in response.json()["detail"]
    assert runner.runs[run_id]["nodes"]["a"]["state"] == "awaiting_gate"


@pytest.mark.parametrize(
    "body",
    [
        {"node": "c"},  # sem modelo
        {"node": "c", "model": ""},
        {"node": "c", "model": "opus; rm -rf /"},
        {"node": "../c", "model": "opus"},
        {"node": "c", "model": "opus", "extra": 1},
    ],
)
def test_upgrade_rejects_bad_body(client, auth, runner, body):
    run_id = start(client, auth)
    runner.force(run_id, "c", "awaiting_upgrade")
    assert client.post(f"/runs/{run_id}/upgrade", json=body, headers=auth).status_code == 422
    assert runner.runs[run_id]["nodes"]["c"]["state"] == "awaiting_upgrade"


def test_quota_warning_is_shown_with_the_engine_limit(client, auth, runner):
    run_id = start(client, auth)
    runner.force(run_id, "b", "awaiting_quota", "quota at 85% (limit 80%) for claude/ambient")
    runner.force(run_id, "c", "awaiting_quota", "cannot read the quota of claude/ambient: timeout")
    view = client.get(f"/runs/{run_id}").json()
    assert node_view(view, "b")["quota_warning"] == "cota acima de 80%"
    assert node_view(view, "c")["quota_warning"]  # leitura falhou: o aviso também aparece
    assert node_view(view, "a")["quota_warning"] is None


# --- segurança -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("path", "body"),
    [
        ("/runs", {"slug": "feat"}),
        ("/runs/feat-00000001/gates/a/approve", None),
        ("/runs/feat-00000001/upgrade", {"node": "c", "model": "opus"}),
    ],
)
def test_post_without_token_is_forbidden(client, auth, runner, path, body):
    start(client, auth)  # cria feat-00000001
    before = {k: v["nodes"] for k, v in runner.runs.items()}
    runs_before = len(runner.runs)
    for headers in ({}, {"X-Flow-Token": ""}, {"X-Flow-Token": "wrong"}, {"X-Flow-Token": TOKEN[:-1]}):
        response = client.post(path, json=body, headers=headers)
        assert response.status_code == 403
        assert TOKEN not in response.text
    assert len(runner.runs) == runs_before
    assert {k: v["nodes"] for k, v in runner.runs.items()} == before


def test_post_token_in_query_or_cookie_does_not_count(client, runner):
    assert client.post(f"/runs?token={TOKEN}", json={"slug": "feat"}).status_code == 403
    client.cookies.set("X-Flow-Token", TOKEN)
    assert client.post("/runs", json={"slug": "feat"}).status_code == 403
    assert runner.runs == {}


@pytest.mark.parametrize(
    "host",
    ["evil.com", "evil.com:8765", "127.0.0.1", "localhost", "127.0.0.1:9999", "localhost:1", "0.0.0.0:8765", "[::1]:8765", ""],
)
def test_invalid_host_is_rejected(client, auth, runner, host):
    for method, path in (("get", "/"), ("get", "/runs/x"), ("post", "/runs")):
        kwargs = {"headers": {"Host": host, **auth}}
        if method == "post":
            kwargs["json"] = {"slug": "feat"}
        response = getattr(client, method)(path, **kwargs)
        assert response.status_code == 400, (host, path)
        assert TOKEN not in response.text
    assert runner.runs == {}


@pytest.mark.parametrize("host", [f"127.0.0.1:{PORT}", f"localhost:{PORT}", f"LOCALHOST:{PORT}"])
def test_valid_hosts_are_accepted(client, host):
    assert client.get("/", headers={"Host": host}).status_code == 200


def test_approve_node_not_awaiting_gate_is_conflict(client, auth, runner):
    run_id = start(client, auth)
    response = client.post(f"/runs/{run_id}/gates/b/approve", headers=auth)  # b está pending
    assert response.status_code == 409
    assert "not awaiting_gate" in response.json()["detail"]
    assert runner.runs[run_id]["nodes"]["b"]["state"] == "pending"
    # Aprovar de novo o nó já aprovado também recusa.
    assert client.post(f"/runs/{run_id}/gates/a/approve", headers=auth).status_code == 200
    assert client.post(f"/runs/{run_id}/gates/a/approve", headers=auth).status_code == 409


def test_unknown_run_and_invalid_ids(client, auth):
    assert client.get("/runs/nope-00000000").status_code == 404
    assert client.get("/runs/..%2F..%2Fetc").status_code in (404, 422)
    assert client.post("/runs/nope-00000000/gates/a/approve", headers=auth).status_code == 404
    assert client.post("/runs/x/gates/..%2Fa/approve", headers=auth).status_code in (404, 422)


def test_start_rejects_bad_slug_and_extra_fields(client, auth, runner):
    for body in ({}, {"slug": ""}, {"slug": "a b"}, {"slug": "../x"}, {"slug": "x" * 200}, {"slug": "x", "repo": "/etc"}):
        assert client.post("/runs", json=body, headers=auth).status_code == 422, body
    assert runner.runs == {}


def test_start_does_not_take_repo_or_flow_from_the_client(client, auth, runner, repo):
    run_id = start(client, auth)
    assert runner.runs[run_id]["repo"] == str(repo)


def test_engine_errors_map_to_http_without_leaking(client, auth, runner):
    runner.raise_on["start_run"] = RepoBusy("repo /r already has an active run: x-1")
    response = client.post("/runs", json={"slug": "feat"}, headers=auth)
    assert response.status_code == 409 and "active run" in response.json()["detail"]

    run_id = start(client, auth, "other")
    runner.raise_on["approve_gate"] = LockTimeout("lock timeout: run busy")
    response = client.post(f"/runs/{run_id}/gates/a/approve", headers=auth)
    assert response.status_code == 503

    runner.raise_on["status"] = RuntimeError(f"boom with {TOKEN}")
    response = client.get(f"/runs/{run_id}")
    assert response.status_code == 500
    assert TOKEN not in response.text and "boom" not in response.text


def test_token_only_in_page_never_in_log_or_other_responses(client, auth, runner, caplog):
    caplog.set_level(logging.DEBUG)
    run_id = start(client, auth)
    runner.raise_on["drive"] = RuntimeError(f"cli said {TOKEN}")  # queda do motor em segundo plano
    responses = [
        client.get(f"/runs/{run_id}"),
        client.post(f"/runs/{run_id}/gates/a/approve", headers=auth),
        client.post(f"/runs/{run_id}/gates/b/approve", headers=auth),
        client.post("/runs", json={"slug": "feat"}, headers={}),
    ]
    assert all(TOKEN not in r.text and TOKEN not in str(r.headers) for r in responses)
    assert TOKEN not in caplog.text
    assert "RuntimeError" in caplog.text  # o log diz o tipo da falha, sem a mensagem


def test_default_token_is_random_per_app(runner, repo, flow_data, write_flow):
    flow = write_flow(flow_data)
    pages = [
        TestClient(create_app(runner, flow_path=flow, repo=repo, port=PORT), base_url=BASE).get("/").text for _ in range(2)
    ]
    tokens = [re.search(r'name="flow-token" content="([^"]+)"', p).group(1) for p in pages]
    assert tokens[0] != tokens[1] and all(len(t) >= 32 for t in tokens)


def test_drive_is_not_started_twice_for_the_same_run(runner, repo, flow_data, write_flow):
    pending = []
    app = create_app(runner, flow_path=write_flow(flow_data), repo=repo, port=PORT, token=TOKEN, spawn=pending.append)
    client = TestClient(app, base_url=BASE)
    auth = {"X-Flow-Token": TOKEN}
    run_id = start(client, auth)
    assert len(pending) == 1
    runner.force(run_id, "a", "awaiting_gate")
    assert client.post(f"/runs/{run_id}/gates/a/approve", headers=auth).status_code == 200
    assert len(pending) == 1  # o motor do run ainda anda: não abre outra execução
    pending.pop()()  # a execução termina e libera o run
    runner.force(run_id, "b", "awaiting_gate")
    assert client.post(f"/runs/{run_id}/gates/b/approve", headers=auth).status_code == 200
    assert len(pending) == 1


# --- bind ----------------------------------------------------------------------------------


def test_main_starts_uvicorn_on_loopback_explicitly(monkeypatch, tmp_path, repo):
    for key, value in {"HOME": str(tmp_path), "PATH": "/usr/bin", "TRAYCER_EPIC_ID": "e", "TRAYCER_AGENT_ID": "a"}.items():
        monkeypatch.setenv(key, value)
    calls = []
    monkeypatch.setattr(server_app.uvicorn, "run", lambda *args, **kwargs: calls.append((args, kwargs)))
    server_app.main(["--repo", str(repo), "--state-dir", str(tmp_path / "state"), "--port", str(PORT)])
    assert HOST == "127.0.0.1"
    (_, kwargs), = calls
    assert kwargs["host"] == "127.0.0.1" and kwargs["port"] == PORT


def test_main_has_no_option_to_change_the_host():
    with pytest.raises(SystemExit):
        server_app.main(["--host", "0.0.0.0"])
