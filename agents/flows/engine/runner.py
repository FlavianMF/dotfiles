"""Motor do fluxo: executa os nós, cria um filho do Traycer por fase e guarda o estado do run em JSON.

Ponto de entrada de biblioteca (o servidor do T5 chama estes métodos):

    runner = Runner(Adapter.from_environ(), state_dir="~/.local/state/flows")
    run_id = runner.start_run("flows/ecc-dev.yaml", slug="minha-feature", repo="/repo")
    runner.drive(run_id)                       # roda até esperar um humano, a cota ou o fim
    runner.status(run_id)                      # estado atual (cópia do JSON mais `waiting`)
    runner.approve_gate(run_id, "plan")        # aprova a parada humana
    runner.choose_upgrade(run_id, "plan", model="opus")  # escolhe o modelo após esgotar a repetição

`step` avança o que dá sem bloquear (uma consulta por filho) e `drive` é o laço que chama `step`
e dorme entre as consultas. Depois de um reinício, `step`/`drive` do mesmo `run_id` retomam: um nó
`running` é rechecado por polling, o filho não é recriado.

Estados do nó (tabela da seção 4 do plano, mais `awaiting_quota`):

    pending -> skipped (when falso) | running | awaiting_gate / done (nó manual) | awaiting_quota
    running -> awaiting_gate | done | failed | awaiting_quota
    failed  -> running (repetição, filho novo) | awaiting_upgrade | aborted (on_fail.then: abort)
    awaiting_gate -> done (aprovado) | running (ajuste pedido) | aborted (recusado)
    awaiting_upgrade -> running (modelo escolhido) | aborted
    awaiting_quota -> running (a cota baixou)

Regras:

- Sucesso de uma fase = todas as saídas existem e mudaram desde o `send` (assinatura mtime+tamanho).
  Um arquivo velho de um run, tentativa ou ajuste anterior não vale. O nó manual só precisa do arquivo.
- O motor nunca espera por `responseId`. O fim do turno vem de `agent list` (ocioso) mais uma
  resposta nova no transcript ou uma saída alterada.
- Antes de criar cada filho (inclusive repetição e upgrade) o motor lê a cota do perfil do nó.
  Passou do limite (estritamente maior que 80%), ou a leitura falhou: `awaiting_quota`, sem filho.
  O provedor sem informação de cota (`None`) não bloqueia.
- Falha repete `on_fail.retry` vezes com filho novo; depois `awaiting_upgrade` (nunca sobe de
  modelo sozinho) ou `aborted` se `on_fail.then` for `abort`.
- Todo filho nasce frio, com o pacote de contexto do motor (até 30 linhas). `context: fork` ainda
  não existe na v1: o motor usa o pacote e registra um evento. Assim a revisão é sempre a frio.
- Um run ativo por repositório (caminho real).
- Recuperação de queda: o nó grava `creating` (nome do filho) antes de `create_child` e `sent_at` antes
  do `send`. Ao retomar, o motor acha o filho órfão pelo nome e o reusa. Se o envio deixou rastro, ele
  só reenvia o prompt quando o filho não mostra mensagem nova, resposta nova, atividade nem saída
  alterada: um prompt já entregue (already delivered) não é enviado de novo. A heurística falha para o
  lado seguro: se o CLI não responde, reenvia (o pior caso é um prompt repetido, não um nó travado).
"""

from __future__ import annotations

import copy
import enum
import os
import re
import subprocess
import time
import uuid
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

from engine.loader import load_flow
from engine.run_state import (
    START_LOCK,
    TERMINAL_NODE_STATES,
    VERSION,
    LockTimeout,
    RunStore,
    StateError,
    add_event,
    iso,
    new_node_state,
    transition,
)
from engine.schema import EFFORTS, Flow, FlowError, Node, prompt_problem
from engine.traycer_cli import Adapter, AgentNotFound, Child, CliError
from engine.validate import execution_order
from engine.when import evaluate_when

PACK_MAX_LINES = 30
PACK_HEADING = "## Pacote de contexto (gerado pelo motor, não é transcript)"


class RunError(Exception):
    """Pedido inválido para o estado atual do run (nó inexistente, estado errado, repo inválido)."""


class RepoBusy(RunError):
    """Já existe um run ativo neste repositório."""


class Step(str, enum.Enum):
    PROGRESS = "progress"  # o estado mudou: chame `step` de novo já
    WAITING = "waiting"  # um filho trabalha: chame `step` depois de `poll_interval`
    BLOCKED = "blocked"  # espera humano, cota ou arquivo: nada a fazer até isso mudar
    FINISHED = "finished"  # run concluído ou abortado


def _git_env() -> dict[str, str]:
    """Ambiente mínimo do git: nada do ambiente do servidor (tokens, GIT_DIR) chega ao processo."""
    env = {
        "HOME": os.environ.get("HOME", "/"),
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": os.environ.get("LANG", "C"),
        "GIT_CONFIG_NOSYSTEM": "1",
    }
    return env


_FLOW_ARTIFACTS = ":(exclude).claude/PRPs"


def _git(repo: str | os.PathLike[str], *args: str) -> subprocess.CompletedProcess:
    """Roda o git com ambiente mínimo e sem o fsmonitor do repo (um repo hostil não executa código)."""
    return subprocess.run(
        ["git", "-c", "core.fsmonitor=false", "-C", str(repo), *args],  # o repo pode apontar o fsmonitor para um script
        env=_git_env(),
        capture_output=True,
        text=True,
        errors="surrogateescape",  # nome de arquivo fora do UTF-8 não derruba a conta
        check=False,
        timeout=60,
    )


def _untracked_lines(repo: str | os.PathLike[str]) -> int:
    """Linhas dos arquivos novos ainda fora do índice (respeita `.gitignore`). Binário conta 0."""
    proc = _git(repo, "ls-files", "-z", "--others", "--exclude-standard", "--", ".", _FLOW_ARTIFACTS)
    if proc.returncode != 0:
        raise RunError(f"git ls-files failed: {proc.stderr.strip()[:200]}")
    total = 0
    for name in proc.stdout.split("\0"):
        if not name:
            continue
        path = Path(repo) / name
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data[:8000]:  # o git trata como binário
            continue
        total += data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)
    return total


def git_variables(repo: str | os.PathLike[str]) -> dict[str, int]:
    """`diff_lines`: linhas adicionadas + removidas do trabalho não commitado.

    Soma `git diff HEAD` (arquivos rastreados) e as linhas dos arquivos novos ainda não adicionados
    ao índice. Ignora `.claude/PRPs/` (os artefatos do próprio fluxo). O git roda com ambiente
    mínimo e sem o fsmonitor, o diff externo e o textconv do repo: um repo hostil não executa
    código aqui."""
    proc = _git(repo, "diff", "HEAD", "--numstat", "--no-ext-diff", "--no-textconv", "--", ".", _FLOW_ARTIFACTS)
    if proc.returncode != 0:
        raise RunError(f"git diff failed: {proc.stderr.strip()[:200]}")
    total = 0
    for line in proc.stdout.splitlines():
        added, removed, _ = (line.split("\t", 2) + ["", "", ""])[:3]
        total += int(added) if added.isdigit() else 0  # binário aparece como "-"
        total += int(removed) if removed.isdigit() else 0
    return {"diff_lines": total + _untracked_lines(repo)}


_BRACKET_PREFIX_RE = re.compile(r"\[\d+:\d+/[^\]]*\]\s*")  # `[48213:1105/...:ERROR:file.cc(9)]` do Chromium
_PID_RE = re.compile(r"\(?\bpid[ =:]*\d+\)?", re.IGNORECASE)
BRIEF_MAX = 140


def _brief(exc: object) -> str:
    """Primeira linha útil do erro do CLI, sem prefixo do Chromium nem PIDs, em até `BRIEF_MAX` caracteres."""
    lines = (line.strip() for line in str(exc).splitlines())
    first = next((line for line in lines if line), "unknown error")
    first = " ".join(_PID_RE.sub("", _BRACKET_PREFIX_RE.sub("", first)).split())
    return first if len(first) <= BRIEF_MAX else first[: BRIEF_MAX - 1] + "…"


def _quota_reading(limits: Any) -> dict[str, Any]:
    return {"five_hour": limits.five_hour, "seven_day": limits.seven_day, "updated_at": limits.updated_at}


class Runner:
    """Motor de fluxo. Ver o docstring do módulo para a API e as regras.

    Concorrência: `step`, `drive` e os métodos que mudam o run seguram a trava do run
    (`RunStore.lock`) do começo ao fim, inclusive durante as chamadas ao CLI do Traycer. Cada
    chamada ao CLI tem teto de 60 s (`Adapter.command_timeout`), então um `step` lento segura a
    trava por esse tempo. Comportamento aceito na v1. Quem espera a trava por mais de
    `lock_timeout` s (30 por padrão) recebe `LockTimeout` (subclasse de `StateError`), que o
    servidor deve tratar (por exemplo, responder "ocupado, tente de novo"). `status` não usa
    a trava: lê o JSON, que é gravado de forma atômica, e responde sem esperar."""

    def __init__(
        self,
        adapter: Adapter,
        *,
        state_dir: str | os.PathLike[str],
        variables_provider: Callable[[Path], Mapping[str, object]] = git_variables,
        quota_threshold: float = 80.0,
        turn_timeout: float = 1800.0,
        poll_interval: float = 5.0,
        now: Callable[[], float] = time.time,
        sleep: Callable[[float], None] = time.sleep,
        lock_timeout: float = 30.0,
    ) -> None:
        self.adapter = adapter
        self.store = RunStore(state_dir, lock_timeout=lock_timeout)
        self._provider = variables_provider
        self._threshold = quota_threshold
        self._turn_timeout = turn_timeout
        self._poll_interval = poll_interval
        self._now = now
        self._sleep = sleep

    # --- API pública ----------------------------------------------------------------------

    def start_run(
        self,
        flow_path: str | os.PathLike[str],
        *,
        slug: str,
        repo: str | os.PathLike[str],
        sensitive: bool = False,
        diff_lines: int | None = None,
    ) -> str:
        """Cria o run (nenhum filho ainda). `FlowError` se o fluxo for inválido, `RepoBusy` se o repo já tem run."""
        if not Path(repo).is_dir():
            raise RunError(f"repo {repo} is not a directory")
        real_repo = os.path.realpath(repo)
        flow = load_flow(flow_path, slug=slug)
        run_id = f"{re.sub(r'[^A-Za-z0-9_-]', '-', slug)[:40]}-{uuid.uuid4().hex[:8]}"
        now = self._now()
        state = {
            "version": VERSION,
            "run_id": run_id,
            "status": "active",
            "flow": flow.name,
            "flow_file": str(flow.source),
            "slug": slug,
            "repo": real_repo,
            "variables": {"sensitive": bool(sensitive), "diff_lines": diff_lines},
            "created_at": iso(now),
            "updated_at": iso(now),
            "nodes": {node.id: new_node_state() for node in flow.nodes},
            "events": [],
        }
        add_event(state, None, f"run created for {real_repo}", now)
        with self.store.lock(START_LOCK):
            for other in self.store.list_runs():
                if other["repo"] == real_repo and other["status"] == "active":
                    raise RepoBusy(f"repo {real_repo} already has an active run: {other['run_id']}")
            self.store.save(state)
        return run_id

    def step(self, run_id: str) -> Step:
        """Avança o que dá sem bloquear e grava o estado."""
        with self.store.lock(run_id):
            state = self.store.load(run_id)
            before = _fingerprint(state)
            flow = self._flow(state)
            result = self._step(state, flow)
            if _fingerprint(state) != before:
                self._save(state)
            return result

    def drive(self, run_id: str, *, max_steps: int | None = None) -> Step:
        """Chama `step` até esperar um humano, a cota ou o fim; dorme `poll_interval` entre as consultas."""
        steps = 0
        while True:
            result = self.step(run_id)
            steps += 1
            if result in (Step.BLOCKED, Step.FINISHED):
                return result
            if max_steps is not None and steps >= max_steps:
                return result
            if result is Step.WAITING:
                self._sleep(self._poll_interval)

    def status(self, run_id: str) -> dict[str, Any]:
        state = self.store.load(run_id)
        view = copy.deepcopy(state)
        view["waiting"] = [
            {"node": node_id, "state": ns["state"]}
            for node_id, ns in state["nodes"].items()
            if ns["state"] in ("awaiting_gate", "awaiting_upgrade", "awaiting_quota")
        ]
        return view

    def approve_gate(self, run_id: str, node_id: str) -> None:
        with self.store.lock(run_id):
            state, flow, node, ns = self._load_node(run_id, node_id)
            self._refresh_manual(state, flow, node, ns)
            if ns["state"] != "awaiting_gate":
                raise RunError(f"node '{node_id}' is {ns['state']}, not awaiting_gate: nothing to approve")
            ns["gate_approved"] = True
            self._to(state, node, "done", "approved by a human")
            self._release(state, node, ns)
            self._save(state)

    def reject_gate(self, run_id: str, node_id: str) -> None:
        """Recusa o portão: o nó e quem depende dele são abortados."""
        with self.store.lock(run_id):
            state, flow, node, ns = self._load_node(run_id, node_id)
            self._require(ns, node_id, "awaiting_gate")
            self._to(state, node, "aborted", "gate rejected by a human")
            self._release(state, node, ns, stop=True)
            self._save(state)

    def request_adjustment(self, run_id: str, node_id: str, note: str) -> None:
        """Volta o nó do portão para `running`: a nota segue para o mesmo filho."""
        with self.store.lock(run_id):
            state, flow, node, ns = self._load_node(run_id, node_id)
            self._require(ns, node_id, "awaiting_gate")
            if not isinstance(note, str) or not note.strip():
                raise RunError("adjustment note must be a non-empty string")
            if not ns["child_id"]:
                raise RunError(f"node '{node_id}' has no child agent (manual node): edit the file and approve")
            outputs = ", ".join(node.outputs)
            ns.update(
                sent=False,
                snapshot=None,
                replies_before=None,  # lidos do transcript no envio
                prompts_before=None,
                sent_at=None,
                retries_used=0,
                pending_message=f"Ajuste pedido por um humano na fase '{node.id}':\n{note.strip()}\n\n"
                f"Reescreva as saídas: {outputs}. O motor só aceita a fase se esses arquivos mudarem.",
            )
            self._to(state, node, "running", "adjustment requested")
            self._save(state)

    def choose_upgrade(self, run_id: str, node_id: str, *, model: str, effort: str | None = None) -> None:
        """Depois de esgotar a repetição, o humano escolhe o modelo (e o esforço) da próxima tentativa."""
        with self.store.lock(run_id):
            state, flow, node, ns = self._load_node(run_id, node_id)
            self._require(ns, node_id, "awaiting_upgrade")
            if not isinstance(model, str) or not model.strip():
                raise RunError("model must be a non-empty string")
            if effort is not None and effort not in EFFORTS:
                raise RunError(f"effort must be one of: {', '.join(EFFORTS)}")
            ns.update(model=model.strip(), retries_used=0)
            if effort is not None:
                ns["effort"] = effort
            self._to(state, node, "running", f"upgrade chosen: {model.strip()}")
            self._save(state)

    def abort_run(self, run_id: str) -> None:
        """Aborta o run: para e arquiva os filhos, aborta os nós abertos e libera o repo."""
        with self.store.lock(run_id):
            state = self.store.load(run_id)
            if state["status"] != "active":
                return
            # Só o estado salvo: o YAML pode ter mudado ou sumido, e abortar tem de funcionar assim mesmo.
            for node_id, ns in state["nodes"].items():
                if ns["state"] not in TERMINAL_NODE_STATES:
                    self._release(state, node_id, ns, stop=True)
                    self._to(state, node_id, "aborted", "run aborted by a human")
            state["status"] = "aborted"
            add_event(state, None, "run aborted", self._now())
            self._save(state)

    # --- passo ----------------------------------------------------------------------------

    def _step(self, state: dict[str, Any], flow: Flow) -> Step:
        if state["status"] != "active":
            return Step.FINISHED
        progressed = waiting = False
        for node in execution_order(flow):
            ns = state["nodes"][node.id]
            if ns["state"] in TERMINAL_NODE_STATES:
                continue
            blockers = [state["nodes"][dep]["state"] for dep in self._deps(flow, node)]
            if "aborted" in blockers:
                self._to(state, node, "aborted", "a predecessor was aborted")
                progressed = True
                continue
            if any(s not in ("done", "skipped") for s in blockers):
                continue
            outcome = self._advance(state, flow, node, ns)
            progressed = progressed or outcome is Step.PROGRESS
            waiting = waiting or outcome is Step.WAITING
        states = [ns["state"] for ns in state["nodes"].values()]
        if all(s in TERMINAL_NODE_STATES for s in states):
            state["status"] = "aborted" if "aborted" in states else "done"
            add_event(state, None, f"run {state['status']}", self._now())
            return Step.FINISHED
        if progressed:
            return Step.PROGRESS
        return Step.WAITING if waiting else Step.BLOCKED

    def _advance(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> Step | None:
        current = ns["state"]
        if current in ("awaiting_gate", "awaiting_upgrade"):
            return None
        if current == "pending":
            if node.when and ns["when_result"] is None and not self._evaluate_when(state, node, ns):
                return Step.PROGRESS
            missing = [p for p in node.inputs if not (Path(state["repo"]) / p).is_file()]
            if missing:
                ns["reason"] = "waiting for input: " + ", ".join(missing)
                return None
            if node.mode == "manual":
                return self._advance_manual(state, node, ns)
            return self._spawn(state, flow, node, ns)
        if current in ("awaiting_quota", "failed"):  # `failed` só persiste no meio de uma repetição
            return self._spawn(state, flow, node, ns)
        if current == "running":
            return self._poll(state, flow, node, ns)
        return None

    def _evaluate_when(self, state: dict[str, Any], node: Node, ns: dict[str, Any]) -> bool:
        """Avalia `when` ao chegar no nó (`diff_lines` só existe depois do implement). True = segue."""
        fixed = {"sensitive": state["variables"]["sensitive"]}
        if state["variables"]["diff_lines"] is not None:
            fixed["diff_lines"] = state["variables"]["diff_lines"]
        try:
            variables = dict(fixed) if "diff_lines" in fixed else {**self._provider(Path(state["repo"])), **fixed}
            result = evaluate_when(node.when or "", variables)
        except Exception as exc:  # noqa: BLE001 (WhenError, git ou provedor injetado: o nó falha, o motor não cai)
            self._to(state, node, "aborted", f"cannot evaluate when {node.when!r}: {_brief(exc)}")
            return False
        ns["when_result"] = result
        if not result:
            self._to(state, node, "skipped", f"when is false: {node.when} {variables}")
            return False
        return True

    def _advance_manual(self, state: dict[str, Any], node: Node, ns: dict[str, Any]) -> Step | None:
        """Nó manual: sem filho. Espera o arquivo de saída e, se houver portão, a aprovação humana."""
        if not self._outputs_exist(state, node):
            ns["reason"] = "waiting for output file: " + ", ".join(node.outputs)
            return None
        if node.gate == "human":
            self._to(state, node, "awaiting_gate", "output exists; waiting for human approval")
        else:
            self._to(state, node, "done", "output exists")
        return Step.PROGRESS

    def _refresh_manual(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> None:
        """Vê o arquivo de um nó manual entre dois steps. Só vale se o nó já pode rodar: predecessores
        done/skipped, `when` avaliado e verdadeiro, entradas presentes. Senão um arquivo velho passaria."""
        if node.mode != "manual" or ns["state"] != "pending" or node.gate != "human":
            return
        if any(state["nodes"][dep]["state"] not in ("done", "skipped") for dep in self._deps(flow, node)):
            return
        if node.when and ns["when_result"] is not True:
            return
        if any(not (Path(state["repo"]) / p).is_file() for p in node.inputs):
            return
        if self._outputs_exist(state, node):
            self._to(state, node, "awaiting_gate", "output exists; waiting for human approval")

    # --- filho ----------------------------------------------------------------------------

    def _spawn(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> Step | None:
        agent = node.agent
        model = ns["model"] or agent.model
        effort = ns["effort"] or agent.effort
        try:
            message = self._message(state, flow, node, ns)
        except (CliError, OSError) as exc:
            return self._fail(state, flow, node, ns, f"cannot create the child: {_brief(exc)}")
        child = None
        name = None
        if ns.get("creating"):  # queda entre `create_child` e o `_save`: procure o filho pelo nome
            name = ns["creating"]["name"]
            try:
                child = self._recover_orphan(ns)
            except CliError as exc:
                ns["reason"] = f"cannot look for an orphan child: {_brief(exc)}"
                return None
        if child is None:
            try:
                limits = self.adapter.rate_limits(agent.harness, agent.profile)
            except CliError as exc:
                return self._wait_quota(state, node, ns, f"cannot read the quota of {agent.harness}/{agent.profile}: {_brief(exc)}")
            percent = limits.used_percent
            if percent is not None and percent > self._threshold:
                return self._wait_quota(
                    state, node, ns, f"quota at {percent:g}% (limit {self._threshold:g}%) for {agent.harness}/{agent.profile}"
                )
            name = f"{flow.name}:{node.id} ({state['run_id'][:12]}) {uuid.uuid4().hex[:8]}"
            ns["creating"] = {"name": name, "model": model, "effort": effort}
            ns["quota_before"] = _quota_reading(limits)
            ns["quota_after"] = None
            self._save(state)  # a marca fica no disco antes do `create_child`: uma queda deixa rastro
            try:
                child = self.adapter.create_child(
                    harness=agent.harness,
                    model=model,
                    effort=effort,
                    profile=agent.profile,
                    cwd=state["repo"],
                    name=name,
                )
            except (CliError, OSError) as exc:
                ns["creating"] = None
                return self._fail(state, flow, node, ns, f"cannot create the child: {_brief(exc)}")
        ns["creating"] = None
        ns.update(
            child_id=child.agent_id,
            child_name=name,  # o título da sessão no Traycer: a página o mostra
            attempts=ns["attempts"] + 1,
            sent=False,
            snapshot=None,
            replies_before=0,
            prompts_before=0,
            sent_at=None,
            pending_message=message,
        )
        if child.diverged:
            ns["divergence"] = {
                "requested": {"model": model, "effort": effort},
                "applied": {"model": child.applied_model, "effort": child.applied_effort},
            }
            add_event(
                state,
                node.id,
                f"requested {model}/{effort} but the Traycer applied {child.applied_model}/{child.applied_effort}",
                self._now(),
            )
        if node.context == "fork":
            add_event(state, node.id, "context fork is not supported in v1: using a cold context pack", self._now())
        if ns["state"] != "running":
            self._to(state, node, "running", f"attempt {ns['attempts']}: {model}/{effort}")
        self._save(state)  # o id do filho fica gravado antes do envio
        self._send(state, flow, node, ns)
        return Step.PROGRESS

    def _recover_orphan(self, ns: dict[str, Any]) -> Child | None:
        """Acha o filho da marca `creating` pelo nome em `agent list`. Reusa o filho vivo (sem criar outro)."""
        mark = ns["creating"]
        found = self.adapter.find_by_name(mark["name"])
        ns["creating"] = None
        if found is None:
            return None
        return Child(found.agent_id, mark["model"], mark["effort"], found.model, found.effort)

    def _wait_quota(self, state: dict[str, Any], node: Node, ns: dict[str, Any], reason: str) -> Step | None:
        if ns["state"] == "awaiting_quota":
            ns["reason"] = reason
            return None
        self._to(state, node, "awaiting_quota", reason)
        return Step.PROGRESS

    def _send(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> None:
        try:
            if ns["replies_before"] is None:
                ns["replies_before"] = self.adapter.reply_count(ns["child_id"])
            if ns["prompts_before"] is None:
                ns["prompts_before"] = self.adapter.prompt_count(ns["child_id"])
            if ns["snapshot"] is None:
                ns["snapshot"] = self._signature(state, node)
            if ns["sent_at"] is not None and self._already_delivered(state, node, ns):
                # Um envio anterior deixou rastro (queda entre o `send` e `sent=True`) e o filho mostra o prompt.
                add_event(state, node.id, "the prompt was already delivered before the restart: not sent again", self._now())
                ns["sent"] = True
                ns["pending_message"] = None
                return
            ns["sent_at"] = self._now()
            self._save(state)
            self.adapter.send(ns["child_id"], ns["pending_message"])
        except CliError as exc:
            self._fail(state, flow, node, ns, f"cannot send the prompt: {_brief(exc)}")
            return
        ns["sent"] = True
        ns["pending_message"] = None

    def _already_delivered(self, state: dict[str, Any], node: Node, ns: dict[str, Any]) -> bool:
        """O filho já recebeu o prompt? Sim se há mensagem nova no transcript, resposta nova, atividade ou
        saída alterada desde antes do envio. Qualquer erro do CLI conta como "não sei": reenvia."""
        child_id = ns["child_id"]
        try:
            return (
                self.adapter.poll_status(child_id).active
                or self.adapter.prompt_count(child_id) > ns["prompts_before"]
                or self.adapter.reply_count(child_id) > ns["replies_before"]
                or self._outputs_changed(state, node, ns)
            )
        except CliError:
            return False

    def _poll(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> Step | None:
        if not ns["child_id"]:  # após `choose_upgrade`
            return self._spawn(state, flow, node, ns)
        if not ns["sent"]:  # reinício entre criar e enviar, ou ajuste pedido
            self._send(state, flow, node, ns)
            return Step.PROGRESS
        child_id = ns["child_id"]
        ended = False
        try:
            info = self.adapter.poll_status(child_id)
        except AgentNotFound:
            return self._fail(state, flow, node, ns, "the child agent is gone from the Task")
        except CliError as exc:
            ns["reason"] = f"polling failed: {_brief(exc)}"  # falha passageira do CLI: o timeout encerra se persistir
        else:
            changed = self._outputs_changed(state, node, ns)
            if not info.active or info.archived:
                try:
                    replied = self.adapter.reply_count(child_id) > ns["replies_before"]
                except CliError:
                    replied = False
                ended = replied or changed or info.archived
            if ended:
                if changed:
                    return self._succeed(state, node, ns)
                return self._fail(state, flow, node, ns, "the child ended its turn without writing the outputs: " + ", ".join(node.outputs))
        elapsed = self._now() - (ns["sent_at"] or self._now())
        if elapsed > self._turn_timeout:
            self._read_quota_after(node, ns)
            self._release(state, node, ns, stop=True)
            return self._fail(state, flow, node, ns, f"timeout: no turn result after {self._turn_timeout:g}s")
        return Step.WAITING

    def _read_quota_after(self, node: Node, ns: dict[str, Any]) -> None:
        """Grava a cota ao fim do turno. A leitura é só medição: se o CLI falhar, fica `None`."""
        try:
            ns["quota_after"] = _quota_reading(self.adapter.rate_limits(node.agent.harness, node.agent.profile))
        except CliError:
            ns["quota_after"] = None

    def _succeed(self, state: dict[str, Any], node: Node, ns: dict[str, Any]) -> Step:
        self._read_quota_after(node, ns)
        if node.gate == "human":
            self._to(state, node, "awaiting_gate", "outputs written; waiting for human approval")
        else:
            self._to(state, node, "done", "outputs written")
            self._release(state, node, ns)
        return Step.PROGRESS

    def _fail(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any], reason: str) -> Step:
        if ns["child_id"]:
            self._read_quota_after(node, ns)
        self._release(state, node, ns, stop=True)
        if ns["state"] in ("pending", "awaiting_quota", "failed"):  # falhou ao criar o filho: a tentativa começou mesmo assim
            ns["attempts"] += 1
            self._to(state, node, "running", f"attempt {ns['attempts']}")
        self._to(state, node, "failed", reason)
        if ns["retries_used"] < node.on_fail.retry:
            ns["retries_used"] += 1
            self._spawn(state, flow, node, ns)
        elif node.on_fail.then == "abort":
            self._to(state, node, "aborted", f"retries exhausted: {reason}")
        else:
            self._to(state, node, "awaiting_upgrade", f"retries exhausted: {reason}")
        return Step.PROGRESS

    def _release(self, state: dict[str, Any], node: Node | str, ns: dict[str, Any], *, stop: bool = False) -> None:
        """Para (opcional) e arquiva o filho do nó. Falha do CLI aqui só vira evento."""
        node_id = node if isinstance(node, str) else node.id
        child_id = ns["child_id"]
        if not child_id:
            return
        for action, label in ((self.adapter.stop if stop else None, "stop"), (self.adapter.archive, "archive")):
            if action is None:
                continue
            try:
                action(child_id)
            except CliError as exc:
                add_event(state, node_id, f"could not {label} child {child_id}: {_brief(exc)}", self._now())
        ns.update(child_id=None, sent=False, snapshot=None, pending_message=None, replies_before=0, prompts_before=0, sent_at=None)
        ns["last_child_id"] = child_id

    # --- mensagem e pacote de contexto -----------------------------------------------------

    def _message(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> str:
        problem = prompt_problem(node.prompt, flow.source.parent)  # confere de novo: um symlink pode ter mudado
        if problem:
            raise PermissionError(f"prompt of node '{node.id}' {problem}")
        text = Path(node.prompt).read_text(encoding="utf-8")
        text = text.replace("${slug}", state["slug"]).replace("{{input}}", ", ".join(node.inputs) or "(nenhuma)")
        return f"{text.rstrip()}\n\n{self._pack(state, flow, node, ns)}\n"

    def _pack(self, state: dict[str, Any], flow: Flow, node: Node, ns: dict[str, Any]) -> str:
        """Decisão, estado e próximo passo em até 30 linhas. Feito do estado do run, não do transcript."""
        decided, remaining = [], []
        for other in flow.nodes:
            other_ns = state["nodes"][other.id]
            if other.id == node.id:
                continue
            if other_ns["state"] in TERMINAL_NODE_STATES:
                how = "aprovado por humano" if other_ns.get("gate_approved") else other_ns["reason"]
                outs = "" if other_ns["state"] != "done" else f" -> {', '.join(other.outputs)}"
                decided.append(f"- {other.id}: {other_ns['state']} ({how}){outs}"[:160])
            else:
                remaining.append(other.id)
        lines = [
            PACK_HEADING,
            f"Run {state['run_id']} · fluxo {flow.name} · slug {state['slug']} · repo {state['repo']}",
            "Decisão:",
        ]
        if len(decided) > 12:
            lines.append(f"- ({len(decided) - 12} fases anteriores omitidas)")
            decided = decided[-12:]
        lines.extend(decided or ["- nenhuma fase anterior"])
        model = ns["model"] or node.agent.model
        lines += [
            "Estado:",
            f"- Fase atual: {node.id} ({node.title}), tentativa {ns['attempts'] + 1}, modelo {model}.",
            "- Fases restantes: " + (", ".join(remaining)[:200] or "nenhuma"),
            "Próximo passo:",
            "- Leia: " + (", ".join(node.inputs) or "(nenhuma entrada)"),
            "- Escreva: " + ", ".join(node.outputs) + ". O motor só aceita a fase se esses arquivos mudarem.",
            "- Não rode as fases seguintes e não edite os arquivos de outras fases.",
        ]
        return "\n".join(lines[:PACK_MAX_LINES])

    # --- arquivos, grafo e estado ----------------------------------------------------------

    @staticmethod
    def _deps(flow: Flow, node: Node) -> list[str]:
        producers = {out: n.id for n in flow.nodes for out in n.outputs}
        deps = [producers[i] for i in node.inputs if i in producers and producers[i] != node.id]
        return list(dict.fromkeys([*deps, *node.after]))

    @staticmethod
    def _outputs_exist(state: dict[str, Any], node: Node) -> bool:
        return all((Path(state["repo"]) / p).is_file() for p in node.outputs)

    @staticmethod
    def _signature(state: dict[str, Any], node: Node) -> dict[str, list[int] | None]:
        sig: dict[str, list[int] | None] = {}
        for p in node.outputs:
            path = Path(state["repo"]) / p
            try:
                st = path.stat()
                sig[p] = [st.st_mtime_ns, st.st_size] if path.is_file() else None
            except OSError:
                sig[p] = None
        return sig

    def _outputs_changed(self, state: dict[str, Any], node: Node, ns: dict[str, Any]) -> bool:
        before = ns["snapshot"] or {}
        now = self._signature(state, node)
        return all(now[p] is not None and now[p] != before.get(p) for p in node.outputs)

    def _to(self, state: dict[str, Any], node: Node | str, to: str, reason: str) -> None:
        node_id = node if isinstance(node, str) else node.id
        ns = state["nodes"][node_id]
        frm = ns["state"]
        transition(ns, to, reason, self._now())
        add_event(state, node_id, f"{frm} -> {to}: {reason}", self._now())

    def _save(self, state: dict[str, Any]) -> None:
        state["updated_at"] = iso(self._now())
        self.store.save(state)

    def _flow(self, state: dict[str, Any]) -> Flow:
        flow = load_flow(state["flow_file"], slug=state["slug"])
        if {n.id for n in flow.nodes} != set(state["nodes"]):
            raise FlowError(f"flow {state['flow_file']} changed its nodes while run {state['run_id']} was open")
        return flow

    def _load_node(self, run_id: str, node_id: str) -> tuple[dict[str, Any], Flow, Node, dict[str, Any]]:
        state = self.store.load(run_id)
        flow = self._flow(state)
        if state["status"] != "active":
            raise RunError(f"run {run_id} is {state['status']}")
        try:
            node = flow.node(node_id)
        except KeyError:
            raise RunError(f"run {run_id} has no node '{node_id}'") from None
        return state, flow, node, state["nodes"][node_id]

    @staticmethod
    def _require(ns: dict[str, Any], node_id: str, expected: str) -> None:
        if ns["state"] != expected:
            raise RunError(f"node '{node_id}' is {ns['state']}, not {expected}")


def _fingerprint(state: dict[str, Any]) -> str:
    import json

    return json.dumps(state, sort_keys=True)


__all__ = ["LockTimeout", "RepoBusy", "RunError", "Runner", "StateError", "Step", "git_variables"]
