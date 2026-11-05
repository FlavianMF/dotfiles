import copy

import pytest

from engine.loader import load_flow
from engine.schema import AgentSpec, Flow, FlowError, Node, OnFail


def load(write_flow, data, slug="feat-x", **kw):
    return load_flow(write_flow(data), slug=slug, **kw)


def errors_of(write_flow, data, slug="feat-x"):
    with pytest.raises(FlowError) as exc:
        load(write_flow, data, slug=slug)
    return exc.value.errors


def test_valid_flow_loads(write_flow, flow_data):
    flow = load(write_flow, flow_data)
    assert isinstance(flow, Flow)
    assert flow.name == "demo"
    assert flow.slug == "feat-x"
    assert [n.id for n in flow.nodes] == ["a", "b", "c"]
    a = flow.nodes[0]
    assert isinstance(a, Node)
    assert a.mode == "manual" and a.gate == "human" and a.context == "pack"
    assert a.agent == AgentSpec("claude", "ambient", "sonnet", "medium", ())
    assert a.on_fail == OnFail(retry=1, then="ask_before_upgrade")
    assert flow.nodes[1].when == "diff_lines > 150 or sensitive"


def test_slug_resolved_in_inputs_outputs_and_run_inputs(write_flow, flow_data):
    flow = load(write_flow, flow_data, slug="my-feature")
    assert flow.run_inputs == ("notes/my-feature.idea.md",)
    a, b, _ = flow.nodes
    assert a.inputs == ("notes/my-feature.idea.md",)
    assert a.outputs == ("out/my-feature.a.md",)
    assert b.inputs == ("out/my-feature.a.md",)
    assert all("${" not in p for n in flow.nodes for p in (*n.inputs, *n.outputs))


def test_defaults(write_flow, flow_data):
    del flow_data["nodes"][1]["when"]
    del flow_data["nodes"][2]["agent"]["skills"]
    flow = load(write_flow, flow_data)
    b, c = flow.nodes[1], flow.nodes[2]
    assert b.when is None and b.mode == "auto"
    assert c.agent.skills == ()


def test_run_inputs_optional(write_flow, node):
    flow = load(write_flow, {"name": "x", "nodes": [node("a", [], ["o.md"])]})
    assert flow.run_inputs == ()


def test_skills_kept_as_tuple(write_flow, flow_data):
    flow_data["nodes"][0]["agent"]["skills"] = ["tdd", "python-reviewer"]
    assert load(write_flow, flow_data).nodes[0].agent.skills == ("tdd", "python-reviewer")


def test_empty_when_null_means_always(write_flow, flow_data):
    flow_data["nodes"][1]["when"] = None
    assert load(write_flow, flow_data).nodes[1].when is None


# --- erros de schema: cada um nomeia o nó e o campo ---------------------------------


@pytest.mark.parametrize(
    "field", ["id", "title", "agent", "prompt", "inputs", "outputs", "gate", "context", "on_fail"]
)
def test_missing_required_field(write_flow, flow_data, field):
    del flow_data["nodes"][1][field]
    errs = errors_of(write_flow, flow_data)
    label = "node #2" if field == "id" else "node 'b'"
    assert any(label in e and f"field '{field}'" in e and "required" in e for e in errs), errs


@pytest.mark.parametrize(
    ("field", "value"),
    [("mode", "semi"), ("gate", "robot"), ("context", "clone")],
)
def test_invalid_enum(write_flow, flow_data, field, value):
    flow_data["nodes"][1][field] = value
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and f"field '{field}'" in e and repr(value) in e for e in errs), errs


@pytest.mark.parametrize(
    ("patch", "field"),
    [
        ({"retry": -1}, "on_fail.retry"),
        ({"retry": "1"}, "on_fail.retry"),
        ({"retry": True}, "on_fail.retry"),
        ({"then": "explode"}, "on_fail.then"),
    ],
)
def test_invalid_on_fail(write_flow, flow_data, patch, field):
    flow_data["nodes"][1]["on_fail"].update(patch)
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and f"field '{field}'" in e for e in errs), errs


@pytest.mark.parametrize("key", ["harness", "profile", "model", "effort"])
def test_agent_requires_key(write_flow, flow_data, key):
    del flow_data["nodes"][1]["agent"][key]
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and f"field 'agent.{key}'" in e for e in errs), errs


def test_agent_skills_must_be_string_list(write_flow, flow_data):
    flow_data["nodes"][1]["agent"]["skills"] = "tdd"
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'agent.skills'" in e for e in errs), errs


def test_unknown_node_field_rejected(write_flow, flow_data):
    flow_data["nodes"][1]["gat"] = "human"
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'gat'" in e and "unknown" in e for e in errs), errs


def test_flow_name_required(write_flow, flow_data):
    del flow_data["name"]
    errs = errors_of(write_flow, flow_data)
    assert any("flow" in e and "field 'name'" in e and "required" in e for e in errs), errs


def test_unknown_top_level_field_rejected(write_flow, flow_data):
    flow_data["nodez"] = []
    errs = errors_of(write_flow, flow_data)
    assert any("flow" in e and "field 'nodez'" in e for e in errs), errs


@pytest.mark.parametrize("bad", ["x +", "foo > 1", "diff_lines > 'a'", "__import__('os')", ""])
def test_invalid_when_expression(write_flow, flow_data, bad):
    flow_data["nodes"][1]["when"] = bad
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'when'" in e for e in errs), errs


@pytest.mark.parametrize("bad_id", ["", "Plan", "has space", "../x", 3])
def test_invalid_node_id(write_flow, flow_data, bad_id):
    flow_data["nodes"][1]["id"] = bad_id
    errs = errors_of(write_flow, flow_data)
    assert any("node #2" in e and "field 'id'" in e for e in errs), errs


@pytest.mark.parametrize("field", ["inputs", "outputs"])
@pytest.mark.parametrize("bad", ["x/${other}.md", "x/${slug.md", "x/${}.md", "x/${ slug }.md"])
def test_inconsistent_placeholder(write_flow, flow_data, field, bad):
    flow_data["nodes"][1][field] = [bad]
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and f"field '{field}'" in e and "placeholder" in e for e in errs), errs


def test_placeholder_in_run_inputs_checked(write_flow, flow_data):
    flow_data["run_inputs"] = ["x/${nope}.md"]
    errs = errors_of(write_flow, flow_data)
    assert any("field 'run_inputs'" in e and "placeholder" in e for e in errs), errs


@pytest.mark.parametrize("bad", ["/etc/passwd", "../outside.md", "a/../../b.md", ""])
def test_unsafe_or_empty_path(write_flow, flow_data, bad):
    flow_data["nodes"][1]["outputs"] = [bad]
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'outputs'" in e for e in errs), errs


@pytest.mark.parametrize("field", ["inputs", "outputs"])
def test_paths_must_be_string_list(write_flow, flow_data, field):
    flow_data["nodes"][1][field] = "x.md"
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and f"field '{field}'" in e for e in errs), errs


def test_paths_are_normalized(write_flow, flow_data):
    flow_data["nodes"][1]["outputs"] = ["./out//${slug}.b.md"]
    assert load(write_flow, flow_data, slug="s").nodes[1].outputs == ("out/s.b.md",)


@pytest.mark.parametrize("slug", ["", "a/b", "..", "a b", "../x", "-x", "x" * 100])
def test_invalid_slug(write_flow, flow_data, slug):
    with pytest.raises(FlowError) as exc:
        load(write_flow, flow_data, slug=slug)
    assert any("slug" in e for e in exc.value.errors)


def test_all_errors_are_reported_together(write_flow, flow_data):
    flow_data["nodes"][0]["gate"] = "robot"
    flow_data["nodes"][2]["context"] = "clone"
    errs = errors_of(write_flow, flow_data)
    assert any("node 'a'" in e for e in errs) and any("node 'c'" in e for e in errs)


@pytest.mark.parametrize("nodes", [None, [], {}, "x"])
def test_nodes_must_be_nonempty_list(write_flow, nodes):
    errs = errors_of(write_flow, {"name": "x", "nodes": nodes})
    assert any("field 'nodes'" in e for e in errs), errs


def test_node_must_be_mapping(write_flow, flow_data):
    flow_data["nodes"][1] = "oops"
    errs = errors_of(write_flow, flow_data)
    assert any("node #2" in e for e in errs), errs


def test_top_level_must_be_mapping(tmp_path):
    p = tmp_path / "f.yaml"
    p.write_text("- a\n- b\n")
    with pytest.raises(FlowError):
        load_flow(p, slug="s")


def test_yaml_syntax_error(tmp_path):
    p = tmp_path / "f.yaml"
    p.write_text("nodes: [unclosed\n")
    with pytest.raises(FlowError, match="YAML"):
        load_flow(p, slug="s")


def test_missing_file(tmp_path):
    with pytest.raises(FlowError, match="cannot read"):
        load_flow(tmp_path / "nope.yaml", slug="s")


def test_load_runs_graph_validation_by_default(write_flow, node):
    data = {"name": "x", "nodes": [node("a", ["missing.md"], ["o.md"])]}
    with pytest.raises(FlowError, match="node 'a'"):
        load(write_flow, data)
    flow = load(write_flow, data, validate=False)
    assert flow.nodes[0].id == "a"


def test_flow_and_nodes_are_immutable(write_flow, flow_data):
    flow = load(write_flow, copy.deepcopy(flow_data))
    with pytest.raises(AttributeError):
        flow.nodes[0].id = "z"  # type: ignore[misc]


@pytest.mark.parametrize("slug", ["abc\n", "abc\x00"])
def test_slug_rejects_trailing_newline_and_nul(write_flow, flow_data, slug):
    with pytest.raises(FlowError):
        load(write_flow, flow_data, slug=slug)


def test_node_id_rejects_trailing_newline(write_flow, flow_data):
    flow_data["nodes"][1]["id"] = "b\n"
    errs = errors_of(write_flow, flow_data)
    assert any("node #2" in e and "field 'id'" in e for e in errs), errs


@pytest.mark.parametrize("bad", ["/etc/passwd", "../../x.md", "a\\b.md", "bad\x00.md", "."])
def test_unsafe_prompt_path(write_flow, flow_data, bad):
    flow_data["nodes"][1]["prompt"] = bad
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'prompt'" in e for e in errs), errs


@pytest.mark.parametrize("bad", [".", "a\\b.md", "bad\x00.md"])
def test_unsafe_io_path(write_flow, flow_data, bad):
    flow_data["nodes"][1]["outputs"] = [bad]
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'outputs'" in e for e in errs), errs


@pytest.mark.parametrize("bad", ["", 0, False, "x"])
def test_run_inputs_must_be_list(write_flow, flow_data, bad):
    flow_data["run_inputs"] = bad
    errs = errors_of(write_flow, flow_data)
    assert any("field 'run_inputs'" in e for e in errs), errs


def test_duplicate_yaml_key_rejected(tmp_path):
    p = tmp_path / "f.yaml"
    p.write_text("name: a\nname: b\nnodes: []\n")
    with pytest.raises(FlowError, match="duplicate key 'name'"):
        load_flow(p, slug="s")


def test_non_utf8_file(tmp_path):
    p = tmp_path / "f.yaml"
    p.write_bytes(b"\xff\xfe\x00bad")
    with pytest.raises(FlowError, match="cannot read"):
        load_flow(p, slug="s")


def test_deeply_nested_when_is_a_flow_error(write_flow, flow_data):
    flow_data["nodes"][1]["when"] = "(" * 400 + "sensitive" + ")" * 400
    errs = errors_of(write_flow, flow_data)
    assert any("node 'b'" in e and "field 'when'" in e for e in errs), errs
