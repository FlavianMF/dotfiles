"""CLI do motor: `python -m engine.cli run|phase|status|approve`. As skills `/flow` e `/phase` chamam este módulo.

    python -m engine.cli run ecc-dev --input "texto da ideia"   # cria o run e avança o que dá
    python -m engine.cli status [--run ID]                      # avança o que dá e mostra o estado
    python -m engine.cli approve plan [--run ID]                # aprova o portão humano do nó
    python -m engine.cli phase plan --input "caminho do PRD"    # uma fase isolada, fora de qualquer run

O processo é local e curto: não há servidor. Quem avança o run é `run`, `status` e `approve`, cada um
com um `step` sem bloqueio (`--no-advance` só lê). Sem `--run`, o comando usa o run ativo do repo.
O repo é `--repo` (padrão: o diretório atual). O estado fica em `--state-dir`
(padrão: `$FLOWS_STATE_DIR` ou `~/.local/state/flows`).

`--input` do `run` vira o slug do run (kebab-case; `--slug` força outro). O motor não guarda o texto:
a fase manual `prd` recebe a ideia do usuário na sessão dele. No `phase`, `--input` substitui
`{{input}}` do prompt (padrão: as entradas do nó).

`phase` não grava estado nem confere as saídas: cria um filho, confere a cota (mesmo limite do motor),
envia o prompt e imprime o id. Com `--wait` espera o fim do turno e diz se as saídas existem.

Saída de erro: exit 2 para pedido inválido (fluxo, nó, run, ambiente), 1 para falha do CLI do Traycer.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from engine.loader import load_flow
from engine.report import cmd_report
from engine.run_state import RunStore, StateError
from engine.runner import RunError, Runner, Step
from engine.schema import SLUG_RE, FlowError
from engine.traycer_cli import Adapter, CliError

FLOWS_DIR = Path(__file__).resolve().parent.parent / "flows"
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
QUOTA_LIMIT = 80.0
MAX_STEPS = 50  # teto de `step` por comando: o laço para em WAITING/BLOCKED/FINISHED antes disso
PHASE_TIMEOUT = 1800.0
PHASE_INTERVAL = 5.0


class UsageError(Exception):
    """Pedido inválido: vira exit 2 com a mensagem."""


def slugify(text: str) -> str:
    """Texto livre em slug kebab-case (até 40 caracteres). Vazio se não sobrar letra ou dígito."""
    ascii_text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", ascii_text.lower()).strip("-")[:40].strip("-")


def resolve_flow(flow: str) -> Path:
    """`ecc-dev` vira `flows/ecc-dev.yaml`. Um caminho existente também vale."""
    if NAME_RE.fullmatch(flow):
        path = FLOWS_DIR / f"{flow}.yaml"
        if path.is_file():
            return path
    elif Path(flow).is_file():
        return Path(flow)
    known = ", ".join(sorted(p.stem for p in FLOWS_DIR.glob("*.yaml"))) or "(nenhum)"
    raise UsageError(f"flow '{flow}' not found. Known flows: {known}")


@dataclass
class Context:
    """Dependências do comando, criadas só quando o comando precisa delas (`phase` não precisa do Runner)."""

    state_dir: Path
    adapter: Adapter | None = None
    runner_factory: Callable[[Adapter, Path], Runner] | None = None
    _runner: Runner | None = field(default=None, init=False, repr=False)

    def get_adapter(self) -> Adapter:
        if self.adapter is None:
            try:
                self.adapter = Adapter.from_environ()
            except ValueError as exc:
                raise UsageError(f"{exc} (run inside a Traycer agent)") from None
        return self.adapter

    def get_runner(self) -> Runner:
        if self._runner is None:
            adapter = self.get_adapter()
            factory = self.runner_factory or (lambda a, d: Runner(a, state_dir=d))
            self._runner = factory(adapter, self.state_dir)
        return self._runner

    @property
    def store(self) -> RunStore:
        return self._runner.store if self._runner else RunStore(self.state_dir)


def default_state_dir() -> Path:
    return Path(os.environ.get("FLOWS_STATE_DIR") or Path.home() / ".local" / "state" / "flows")


def active_run(store: RunStore, repo: str) -> dict[str, Any] | None:
    real = os.path.realpath(repo)
    runs = [r for r in store.list_runs() if r["repo"] == real and r["status"] == "active"]
    return runs[0] if runs else None


def _run_id(ctx: Context, repo: str, explicit: str | None) -> str:
    if explicit:
        return explicit
    found = active_run(ctx.store, repo)
    if not found:
        raise UsageError(f"no active run in {os.path.realpath(repo)}: pass --run ID or start one with `run`")
    return found["run_id"]


def advance(runner: Runner, run_id: str) -> Step:
    """Chama `step` até esperar (filho, humano, cota) ou o fim. Não dorme: o próximo comando retoma."""
    result = Step.PROGRESS
    for _ in range(MAX_STEPS):
        result = runner.step(run_id)
        if result is not Step.PROGRESS:
            break
    return result


def format_status(view: dict[str, Any], step: Step | None = None) -> str:
    lines = [f"run {view['run_id']} · fluxo {view['flow']} · slug {view['slug']} · {view['status']}"]
    lines.append(f"repo {view['repo']}")
    for node_id, ns in view["nodes"].items():
        reason = f" — {ns['reason']}" if ns.get("reason") else ""
        lines.append(f"  {node_id:<12} {ns['state']}{reason}")
    if view["waiting"]:
        lines.append("espera você: " + ", ".join(f"{w['node']} ({w['state']})" for w in view["waiting"]))
    if step is not None:
        lines.append(f"motor: {step.value}")
    return "\n".join(lines)


def _print_status(runner: Runner, run_id: str, step: Step | None, as_json: bool) -> None:
    view = runner.status(run_id)
    print(json.dumps(view, ensure_ascii=False, indent=2) if as_json else format_status(view, step))


# --- comandos -------------------------------------------------------------------------------


def cmd_run(args: argparse.Namespace, ctx: Context) -> int:
    flow_path = resolve_flow(args.flow)
    slug = args.slug or slugify(args.input or "")
    if not slug:
        raise UsageError("pass --input TEXT (it becomes the slug) or --slug")
    if not SLUG_RE.fullmatch(slug):
        raise UsageError(f"invalid slug '{slug}'")
    runner = ctx.get_runner()
    run_id = runner.start_run(flow_path, slug=slug, repo=args.repo, sensitive=args.sensitive)
    step = advance(runner, run_id)
    _print_status(runner, run_id, step, args.json)
    return 0


def cmd_status(args: argparse.Namespace, ctx: Context) -> int:
    runner = ctx.get_runner()
    run_id = _run_id(ctx, args.repo, args.run)
    step = None if args.no_advance else advance(runner, run_id)
    _print_status(runner, run_id, step, args.json)
    return 0


def cmd_approve(args: argparse.Namespace, ctx: Context) -> int:
    runner = ctx.get_runner()
    run_id = _run_id(ctx, args.repo, args.run)
    runner.approve_gate(run_id, args.node)
    step = advance(runner, run_id)
    _print_status(runner, run_id, step, args.json)
    return 0


def render_phase_prompt(node_prompt: str, slug: str, text: str) -> str:
    return Path(node_prompt).read_text(encoding="utf-8").replace("${slug}", slug).replace("{{input}}", text).rstrip() + "\n"


def _release_child(adapter: Adapter, agent_id: str, *, stop: bool) -> None:
    """Para (só em erro: o turno pode estar em curso) e arquiva o filho. Falha vira aviso, não esconde o erro original."""
    for label, action in (("stop", adapter.stop if stop else None), ("archive", adapter.archive)):
        if action is None:
            continue
        try:
            action(agent_id)
        except CliError as exc:
            print(f"warning: could not {label} child {agent_id}: {exc}", file=sys.stderr)


def cmd_phase(args: argparse.Namespace, ctx: Context) -> int:
    flow_path = resolve_flow(args.flow)
    found = active_run(ctx.store, args.repo)
    slug = args.slug or (found["slug"] if found else None) or slugify(args.input or "")
    if not slug or not SLUG_RE.fullmatch(slug):
        raise UsageError("cannot find the slug: pass --slug (or --input TEXT to derive it)")
    flow = load_flow(flow_path, slug=slug)
    try:
        node = flow.node(args.node)
    except KeyError:
        raise UsageError(f"flow {flow.name} has no node '{args.node}'. Nodes: {', '.join(n.id for n in flow.nodes)}") from None
    if node.mode == "manual":
        raise UsageError(f"node '{node.id}' is manual: run its prompt in your own session ({node.prompt})")
    text = args.input if args.input is not None else (", ".join(node.inputs) or "(nenhuma)")
    message = render_phase_prompt(node.prompt, slug, text)
    adapter = ctx.get_adapter()
    agent = node.agent
    percent = adapter.rate_limit_used_percent(agent.harness, agent.profile)
    if percent is not None and percent > QUOTA_LIMIT:
        raise CliError(f"quota at {percent:g}% (limit {QUOTA_LIMIT:g}%) for {agent.harness}/{agent.profile}: not creating the child")
    child = adapter.create_child(
        harness=agent.harness,
        model=agent.model,
        effort=agent.effort,
        profile=agent.profile,
        cwd=os.path.realpath(args.repo),
        name=f"phase:{node.id} ({slug})",
    )
    done = False
    try:
        replies = adapter.reply_count(child.agent_id)
        adapter.send(child.agent_id, message)
        print(f"phase {node.id}: child {child.agent_id} · {agent.harness}/{child.applied_model or agent.model}/{child.applied_effort or agent.effort}")
        print("outputs: " + ", ".join(node.outputs))
        if args.wait:
            adapter.wait_turn_end(child.agent_id, timeout=PHASE_TIMEOUT, interval=PHASE_INTERVAL, replies_before=replies)
            for out in node.outputs:
                print(f"  {'ok     ' if (Path(args.repo) / out).is_file() else 'missing'} {out}")
        done = True
    finally:
        # Sem `--wait` o filho segue vivo para o usuário abrir. Em erro, ou com `--wait`, ninguém mais o usa.
        if args.wait or not done:
            _release_child(adapter, child.agent_id, stop=not done)
    return 0


# --- entrada --------------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--repo", default=os.getcwd(), help="raiz do repo do trabalho (padrão: diretório atual)")
    common.add_argument("--state-dir", default=None, help="estado dos runs (padrão: $FLOWS_STATE_DIR ou ~/.local/state/flows)")
    common.add_argument("--json", action="store_true", help="imprime o estado como JSON")
    parser = argparse.ArgumentParser(prog="engine.cli", description="Roda fluxos de agentes pelo motor local.")
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", parents=[common], help="inicia um fluxo")
    run.add_argument("flow", help="nome do fluxo (flows/<nome>.yaml) ou caminho do YAML")
    run.add_argument("--input", help="texto da ideia: vira o slug do run")
    run.add_argument("--slug", help="slug explícito (substitui o derivado de --input)")
    run.add_argument("--sensitive", action="store_true", help="marca o run como sensível (variável `sensitive` do when)")
    run.set_defaults(func=cmd_run)

    status = sub.add_parser("status", parents=[common], help="mostra o estado e avança o que dá")
    status.add_argument("--run", help="id do run (padrão: o run ativo do repo)")
    status.add_argument("--no-advance", action="store_true", help="só lê, não avança o run")
    status.set_defaults(func=cmd_status)

    approve = sub.add_parser("approve", parents=[common], help="aprova o portão humano de um nó")
    approve.add_argument("node", help="id do nó")
    approve.add_argument("--run", help="id do run (padrão: o run ativo do repo)")
    approve.set_defaults(func=cmd_approve)

    phase = sub.add_parser("phase", parents=[common], help="roda uma fase isolada, sem run")
    phase.add_argument("node", help="id do nó")
    phase.add_argument("--input", help="texto que substitui {{input}} do prompt (padrão: as entradas do nó)")
    phase.add_argument("--flow", default="ecc-dev", help="fluxo do nó (padrão: ecc-dev)")
    phase.add_argument("--slug", help="slug (padrão: o do run ativo do repo, ou derivado de --input)")
    phase.add_argument("--wait", action="store_true", help="espera o fim do turno e confere as saídas")
    phase.set_defaults(func=cmd_phase)

    rep = sub.add_parser("report", parents=[common], help="relatório por fase de um run (modelo, duração, contexto, cota)")
    rep.add_argument("run", help="id do run")
    rep.set_defaults(func=cmd_report)
    return parser


def main(
    argv: Sequence[str] | None = None,
    *,
    adapter: Adapter | None = None,
    runner_factory: Callable[[Adapter, Path], Runner] | None = None,
) -> int:
    """`adapter` e `runner_factory` existem para os testes injetarem o CLI falso."""
    args = build_parser().parse_args(argv)
    state_dir = Path(args.state_dir) if args.state_dir else default_state_dir()
    try:
        return args.func(args, Context(state_dir, adapter, runner_factory))
    except (UsageError, FlowError, RunError, StateError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except CliError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
