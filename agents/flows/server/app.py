"""App FastAPI do T5: página de botões e API fina sobre o motor (`Runner`).

Rotas:

    GET  /                              página única (sem build, sem CDN), com o token embutido
    POST /runs                          {"slug": "..."}: cria o run e põe o motor para andar
    GET  /runs/{id}                     estado das fases (JSON do motor, mais saídas e avisos)
    POST /runs/{id}/gates/{node}/approve   aprova a parada humana de um nó em `awaiting_gate`
    POST /runs/{id}/upgrade             {"node", "model", "effort"?}: escolhe o modelo de um nó em `awaiting_upgrade`

Segurança (local, um usuário):

- O bind é sempre `127.0.0.1` (`HOST`, sem opção para mudar).
- O cabeçalho `Host` só pode ser `127.0.0.1:<porta>` ou `localhost:<porta>`: barra DNS rebinding.
- Todo método que escreve exige `X-Flow-Token`, um token novo a cada partida embutido na página.
  Sem ele ou com outro valor: 403. Um site de fora não lê a página (Host e CORS) nem envia o cabeçalho.
- O fluxo e o repo vêm da linha de comando, não do cliente. O cliente só escolhe o `slug`, que tem formato fixo.
- Nada de `eval` nem de shell. O token não vai para log nem para resposta além da própria página.
  Erro inesperado vira "internal error" e o log só registra o tipo da exceção.
"""

from __future__ import annotations

import argparse
import hmac
import logging
import os
import re
import secrets
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi import Path as PathParam
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from engine.loader import load_flow
from engine.run_state import RUN_ID_RE, LockTimeout, StateError
from engine.runner import RepoBusy, RunError, Runner
from engine.schema import NODE_ID_RE, SLUG_RE, FlowError
from engine.traycer_cli import Adapter

HOST = "127.0.0.1"  # nunca o padrão da ferramenta nem uma interface de rede
DEFAULT_PORT = 8765
TOKEN_HEADER = "X-Flow-Token"
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
FLOWS_DIR = Path(__file__).resolve().parent.parent
PAGE = Path(__file__).resolve().parent / "static" / "index.html"

REASON_MAX = 300
EVENTS_SHOWN = 20
QUOTA_RE = re.compile(r"quota at [\d.]+% \(limit ([\d.]+)%\)")
RUN_ID_PATTERN = RUN_ID_RE.pattern
NODE_ID_PATTERN = NODE_ID_RE.pattern

log = logging.getLogger("flows.server")


class StartBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    slug: str = Field(pattern=SLUG_RE.pattern)
    sensitive: bool = False


class UpgradeBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    node: str = Field(pattern=NODE_ID_PATTERN)
    model: str = Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$")
    effort: str | None = Field(default=None, pattern=r"^[a-z]{1,16}$")  # o motor valida o valor


def _fail(status: int, detail: str) -> HTTPException:
    return HTTPException(status_code=status, detail=detail)


def _engine(call: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
    """Chama o motor e traduz os erros dele em HTTP, sem vazar mensagem de erro inesperado."""
    try:
        return call(*args, **kwargs)
    except LockTimeout as exc:
        raise _fail(503, "run is busy, try again") from exc
    except StateError as exc:
        raise _fail(404, "run not found") from exc
    except RepoBusy as exc:
        raise _fail(409, str(exc)) from exc
    except RunError as exc:
        raise _fail(409, str(exc)) from exc
    except FlowError as exc:
        raise _fail(422, str(exc)[:REASON_MAX]) from exc
    except Exception as exc:
        log.error("engine call failed: %s", type(exc).__name__)
        raise _fail(500, "internal error") from exc


class RunView:
    """Monta a resposta de `GET /runs/{id}` a partir do JSON do motor, sem guardar estado do run."""

    def __init__(self) -> None:
        self._flows: dict[tuple[str, str], list[tuple[str, str, tuple[str, ...]]]] = {}

    def _layout(self, state: dict[str, Any]) -> list[tuple[str, str, tuple[str, ...]]]:
        """(id, título, saídas) na ordem do YAML. O JSON do motor grava as chaves em ordem alfabética."""
        key = (str(state.get("flow_file", "")), str(state.get("slug", "")))
        if key not in self._flows:
            try:
                flow = load_flow(key[0], slug=key[1], validate=False)
                self._flows[key] = [(n.id, n.title, n.outputs) for n in flow.nodes]
            except FlowError:
                return [(node_id, node_id, ()) for node_id in state["nodes"]]  # YAML sumiu: sem saídas, sem cache
        return self._flows[key]

    def build(self, state: dict[str, Any]) -> dict[str, Any]:
        repo = Path(str(state.get("repo", "")))
        active = state.get("status") == "active"
        layout = self._layout(state)
        known = {node_id for node_id, _, _ in layout}
        layout = layout + [(n, n, ()) for n in state["nodes"] if n not in known]
        nodes = []
        for node_id, title, outputs in layout:
            ns = state["nodes"].get(node_id)
            if ns is None:
                continue
            reason = str(ns.get("reason") or "")[:REASON_MAX]
            nodes.append(
                {
                    "id": node_id,
                    "title": title,
                    "state": ns["state"],
                    "reason": reason,
                    "outputs": [{"path": p, "exists": _is_file(repo, p)} for p in outputs],
                    "quota_warning": _quota_warning(ns["state"], reason),
                    "actions": _actions(ns["state"]) if active else [],
                }
            )
        return {
            "run_id": state["run_id"],
            "status": state["status"],
            "flow": state.get("flow"),
            "slug": state.get("slug"),
            "nodes": nodes,
            "waiting": state.get("waiting", []),
            "events": state.get("events", [])[-EVENTS_SHOWN:],
        }


def _is_file(repo: Path, relative: str) -> bool:
    try:
        return (repo / relative).is_file()
    except OSError:
        return False


def _actions(node_state: str) -> list[str]:
    return {"awaiting_gate": ["approve"], "awaiting_upgrade": ["upgrade"]}.get(node_state, [])


def _quota_warning(node_state: str, reason: str) -> str | None:
    if node_state != "awaiting_quota":
        return None
    match = QUOTA_RE.search(reason)
    return f"cota acima de {match.group(1)}%" if match else "cota ilegível: o motor espera"


def _thread_spawn(fn: Callable[[], None]) -> None:
    threading.Thread(target=fn, name="flow-drive", daemon=True).start()


def create_app(
    runner: Runner,
    *,
    flow_path: str | Path,
    repo: str | Path,
    port: int = DEFAULT_PORT,
    token: str | None = None,
    spawn: Callable[[Callable[[], None]], None] = _thread_spawn,
    resume: bool = False,
) -> FastAPI:
    token = token or secrets.token_urlsafe(32)
    allowed_hosts = frozenset({f"{HOST}:{port}", f"localhost:{port}"})
    page = PAGE.read_text(encoding="utf-8")
    view = RunView()
    driving: set[str] = set()
    again: set[str] = set()  # kicks que chegaram com a thread do run ainda viva
    guard = threading.Lock()

    def kick(run_id: str) -> None:
        """Põe o motor para andar em segundo plano, no máximo uma thread por run.

        Se a thread do run ainda existe, ela pode já ter decidido parar (`BLOCKED`) antes da mudança
        que motivou este `kick`. Por isso o id vai para `again` e a thread repete o `drive`."""
        with guard:
            if run_id in driving:
                again.add(run_id)
                return
            driving.add(run_id)

        def work() -> None:
            try:
                while True:
                    runner.drive(run_id)
                    with guard:
                        if run_id not in again:
                            driving.discard(run_id)
                            return
                        again.discard(run_id)
            except BaseException as exc:  # o estado do run guarda a causa; o log só diz o tipo
                with guard:
                    driving.discard(run_id)
                    again.discard(run_id)
                if not isinstance(exc, Exception):
                    raise
                log.error("drive of run %s stopped: %s", run_id, type(exc).__name__)

        spawn(work)

    def resume_active_runs() -> None:
        """Depois de um reinício, religa os runs ativos deste repo e deste fluxo (o motor rechecha os filhos)."""
        try:
            runs = runner.store.list_runs()
        except Exception as exc:
            log.error("cannot list runs to resume: %s", type(exc).__name__)
            return
        mine = (os.path.realpath(repo), os.path.realpath(flow_path))
        for state in runs:
            ours = (os.path.realpath(str(state.get("repo", ""))), os.path.realpath(str(state.get("flow_file", ""))))
            if state.get("status") == "active" and ours == mine:
                kick(state["run_id"])

    app = FastAPI(title="flows", docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def protect(request: Request, call_next: Callable[[Request], Any]) -> Any:
        if request.headers.get("host", "").lower() not in allowed_hosts:
            return JSONResponse({"detail": "invalid host"}, status_code=400)
        if request.method not in SAFE_METHODS:
            sent = request.headers.get(TOKEN_HEADER, "")
            if not hmac.compare_digest(sent.encode(), token.encode()):
                return JSONResponse({"detail": "missing or invalid token"}, status_code=403)
        return await call_next(request)

    @app.get("/", response_class=HTMLResponse)
    def index() -> HTMLResponse:
        nonce = secrets.token_urlsafe(16)
        body = page.replace("__TOKEN__", token).replace("__NONCE__", nonce)
        csp = (
            f"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; "
            "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        )
        return HTMLResponse(body, headers={"Cache-Control": "no-store", "Content-Security-Policy": csp})

    @app.post("/runs", status_code=201)
    def start_run(body: StartBody) -> dict[str, Any]:
        run_id = _engine(runner.start_run, flow_path, slug=body.slug, repo=repo, sensitive=body.sensitive)
        kick(run_id)
        return {"run_id": run_id}

    @app.get("/runs/{run_id}")
    def get_run(run_id: str = PathParam(pattern=RUN_ID_PATTERN)) -> dict[str, Any]:
        return _engine(view.build, _engine(runner.status, run_id))

    @app.post("/runs/{run_id}/gates/{node}/approve")
    def approve(
        run_id: str = PathParam(pattern=RUN_ID_PATTERN), node: str = PathParam(pattern=NODE_ID_PATTERN)
    ) -> dict[str, Any]:
        _engine(runner.approve_gate, run_id, node)
        kick(run_id)
        return _engine(view.build, _engine(runner.status, run_id))

    @app.post("/runs/{run_id}/upgrade")
    def upgrade(body: UpgradeBody, run_id: str = PathParam(pattern=RUN_ID_PATTERN)) -> dict[str, Any]:
        _engine(runner.choose_upgrade, run_id, body.node, model=body.model, effort=body.effort)
        kick(run_id)
        return _engine(view.build, _engine(runner.status, run_id))

    if resume:
        resume_active_runs()
    return app


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="python -m server.app", description="Servidor local dos fluxos (127.0.0.1).")
    parser.add_argument("--flow", default=str(FLOWS_DIR / "flows" / "ecc-dev.yaml"))
    parser.add_argument("--repo", default=".", help="repositório onde o fluxo roda")
    parser.add_argument("--state-dir", default="~/.local/state/flows")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args(argv)
    try:
        adapter = Adapter.from_environ()
    except ValueError as exc:
        parser.error(str(exc))
    runner = Runner(adapter, state_dir=Path(args.state_dir).expanduser())
    app = create_app(runner, flow_path=args.flow, repo=Path(args.repo).resolve(), port=args.port, resume=True)
    print(f"flows: http://{HOST}:{args.port}/")
    uvicorn.run(app, host=HOST, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
