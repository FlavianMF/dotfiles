"""Lê o YAML do fluxo, aplica o schema, resolve `${slug}` e valida o grafo.

    load_flow(path, slug="minha-feature") -> Flow

Levanta `FlowError` (com todos os problemas) se o YAML ou o grafo forem inválidos.
"""

from __future__ import annotations

import posixpath
from pathlib import Path, PurePosixPath
from typing import Any

import yaml

from engine.schema import (
    CONTEXTS,
    FLOW_FIELDS,
    GATES,
    MODES,
    NODE_ID_RE,
    ON_FAIL_THEN,
    OPTIONAL_AGENT_FIELDS,
    OPTIONAL_NODE_FIELDS,
    REQUIRED_AGENT_FIELDS,
    REQUIRED_NODE_FIELDS,
    REQUIRED_ON_FAIL_FIELDS,
    SLUG_RE,
    AgentSpec,
    Flow,
    FlowError,
    Node,
    OnFail,
)
from engine.validate import validate_flow
from engine.when import WhenError, parse_when

_SLUG_PLACEHOLDER = "${slug}"


def _fmt(value: Any) -> str:
    return repr(value)


def _is_str(value: Any) -> bool:
    return isinstance(value, str) and value.strip() != ""


class _Collector:
    """Junta erros de um nó (ou do fluxo) com o prefixo `node 'id': field 'x': ...`."""

    def __init__(self, label: str, errors: list[str]) -> None:
        self.label = label
        self.errors = errors

    def add(self, field: str, message: str) -> None:
        self.errors.append(f"{self.label}: field '{field}': {message}")


def _expect_enum(c: _Collector, field: str, value: Any, allowed: tuple[str, ...]) -> bool:
    if value not in allowed or not isinstance(value, str):
        c.add(field, f"invalid value {_fmt(value)} (expected one of: {', '.join(allowed)})")
        return False
    return True


def _resolve_path(c: _Collector, field: str, raw: Any, slug: str) -> str | None:
    if not _is_str(raw):
        c.add(field, f"path must be a non-empty string, got {_fmt(raw)}")
        return None
    if "${" in raw.replace(_SLUG_PLACEHOLDER, ""):
        c.add(field, f"invalid placeholder in {_fmt(raw)} (only ${{slug}} is allowed)")
        return None
    path = raw.replace(_SLUG_PLACEHOLDER, slug)
    if path.startswith("/") or ".." in PurePosixPath(path).parts:
        c.add(field, f"path {_fmt(raw)} must be relative to the repo root and stay inside it")
        return None
    return posixpath.normpath(path)


def _resolve_paths(c: _Collector, field: str, raw: Any, slug: str) -> tuple[str, ...]:
    if not isinstance(raw, list):
        c.add(field, f"must be a list of paths, got {_fmt(raw)}")
        return ()
    resolved = (_resolve_path(c, field, item, slug) for item in raw)
    return tuple(p for p in resolved if p is not None)


def _parse_agent(c: _Collector, raw: Any) -> AgentSpec | None:
    if not isinstance(raw, dict):
        c.add("agent", f"must be a mapping, got {_fmt(raw)}")
        return None
    ok = True
    for key in raw:
        if key not in (*REQUIRED_AGENT_FIELDS, *OPTIONAL_AGENT_FIELDS):
            c.add(f"agent.{key}", "unknown field")
            ok = False
    for key in REQUIRED_AGENT_FIELDS:
        if key not in raw:
            c.add(f"agent.{key}", "required field is missing")
            ok = False
        elif not _is_str(raw[key]):
            c.add(f"agent.{key}", f"must be a non-empty string, got {_fmt(raw[key])}")
            ok = False
    skills = raw.get("skills", [])
    if skills is None:
        skills = []
    if not isinstance(skills, list) or not all(_is_str(s) for s in skills):
        c.add("agent.skills", f"must be a list of strings, got {_fmt(skills)}")
        ok = False
    if not ok:
        return None
    return AgentSpec(raw["harness"], raw["profile"], raw["model"], raw["effort"], tuple(skills))


def _parse_on_fail(c: _Collector, raw: Any) -> OnFail | None:
    if not isinstance(raw, dict):
        c.add("on_fail", f"must be a mapping, got {_fmt(raw)}")
        return None
    ok = True
    for key in raw:
        if key not in REQUIRED_ON_FAIL_FIELDS:
            c.add(f"on_fail.{key}", "unknown field")
            ok = False
    for key in REQUIRED_ON_FAIL_FIELDS:
        if key not in raw:
            c.add(f"on_fail.{key}", "required field is missing")
            ok = False
    if not ok:
        return None
    retry = raw["retry"]
    if isinstance(retry, bool) or not isinstance(retry, int) or retry < 0:
        c.add("on_fail.retry", f"must be an integer >= 0, got {_fmt(retry)}")
        ok = False
    if not _expect_enum(c, "on_fail.then", raw["then"], ON_FAIL_THEN):
        ok = False
    return OnFail(retry, raw["then"]) if ok else None


def _parse_node(raw: Any, index: int, slug: str, errors: list[str]) -> Node | None:
    node_id = raw.get("id") if isinstance(raw, dict) else None
    label = f"node '{node_id}'" if isinstance(node_id, str) and NODE_ID_RE.match(node_id) else f"node #{index}"
    c = _Collector(label, errors)
    if not isinstance(raw, dict):
        errors.append(f"{label}: must be a mapping, got {_fmt(raw)}")
        return None
    before = len(errors)

    for key in raw:
        if key not in (*REQUIRED_NODE_FIELDS, *OPTIONAL_NODE_FIELDS):
            c.add(key, "unknown field")
    for key in REQUIRED_NODE_FIELDS:
        if key not in raw:
            c.add(key, "required field is missing")
    if "id" in raw and label.startswith("node #"):
        c.add("id", f"must match {NODE_ID_RE.pattern}, got {_fmt(node_id)}")

    for key in ("title", "prompt"):
        if key in raw and not _is_str(raw[key]):
            c.add(key, f"must be a non-empty string, got {_fmt(raw[key])}")

    mode = raw.get("mode", OPTIONAL_NODE_FIELDS["mode"])
    _expect_enum(c, "mode", mode, MODES)
    if "gate" in raw:
        _expect_enum(c, "gate", raw["gate"], GATES)
    if "context" in raw:
        _expect_enum(c, "context", raw["context"], CONTEXTS)

    when = raw.get("when")
    if when is not None:
        try:
            parse_when(when)
        except WhenError as exc:
            c.add("when", f"invalid expression {_fmt(when)}: {exc}")

    agent = _parse_agent(c, raw["agent"]) if "agent" in raw else None
    on_fail = _parse_on_fail(c, raw["on_fail"]) if "on_fail" in raw else None
    inputs = _resolve_paths(c, "inputs", raw["inputs"], slug) if "inputs" in raw else ()
    outputs = _resolve_paths(c, "outputs", raw["outputs"], slug) if "outputs" in raw else ()

    if len(errors) > before:
        return None
    return Node(
        id=raw["id"],
        title=raw["title"],
        mode=mode,
        agent=agent,  # type: ignore[arg-type]
        prompt=raw["prompt"],
        inputs=inputs,
        outputs=outputs,
        gate=raw["gate"],
        when=when,
        context=raw["context"],
        on_fail=on_fail,  # type: ignore[arg-type]
    )


def parse_flow(data: Any, slug: str) -> Flow:
    """Aplica o schema a um dict já lido do YAML e resolve `${slug}`. Não checa o grafo."""
    errors: list[str] = []
    if not isinstance(slug, str) or not SLUG_RE.match(slug):
        errors.append(f"flow: field 'slug': invalid slug {_fmt(slug)} (expected {SLUG_RE.pattern})")
        slug = "invalid"
    if not isinstance(data, dict):
        raise FlowError(errors + [f"flow: top level must be a mapping, got {type(data).__name__}"])
    c = _Collector("flow", errors)
    for key in data:
        if key not in FLOW_FIELDS:
            c.add(key, "unknown field")
    if not _is_str(data.get("name")):
        c.add("name", "required field is missing or not a non-empty string")
    run_inputs = _resolve_paths(c, "run_inputs", data.get("run_inputs") or [], slug)

    raw_nodes = data.get("nodes")
    nodes: list[Node] = []
    if not isinstance(raw_nodes, list) or not raw_nodes:
        c.add("nodes", f"must be a non-empty list, got {_fmt(raw_nodes)}")
    else:
        for index, raw in enumerate(raw_nodes, start=1):
            node = _parse_node(raw, index, slug, errors)
            if node is not None:
                nodes.append(node)
    if errors:
        raise FlowError(errors)
    return Flow(name=data["name"], slug=slug, run_inputs=run_inputs, nodes=tuple(nodes))


def load_flow(path: str | Path, *, slug: str, validate: bool = True) -> Flow:
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise FlowError(f"flow: cannot read {path}: {exc.strerror or exc}") from exc
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise FlowError(f"flow: invalid YAML in {path}: {exc}") from exc
    flow = parse_flow(data, slug)
    if validate:
        validate_flow(flow)
    return flow
