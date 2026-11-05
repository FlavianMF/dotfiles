import pytest

from engine.loader import load_flow
from engine.schema import FlowError
from engine.validate import check_flow, execution_order, validate_flow


def flow_of(write_flow, data, slug="s"):
    return load_flow(write_flow(data), slug=slug, validate=False)


def errors_of(write_flow, data, slug="s"):
    flow = flow_of(write_flow, data, slug)
    errs = check_flow(flow)
    with pytest.raises(FlowError) as exc:
        validate_flow(flow)
    assert exc.value.errors == errs
    return errs


def test_valid_flow_passes(write_flow, flow_data):
    flow = flow_of(write_flow, flow_data)
    assert check_flow(flow) == []
    validate_flow(flow)


def test_run_input_satisfies_input(write_flow, node):
    data = {"name": "x", "run_inputs": ["idea.md"], "nodes": [node("a", ["idea.md"], ["o.md"])]}
    validate_flow(flow_of(write_flow, data))


def test_duplicate_node_id(write_flow, node):
    data = {"name": "x", "nodes": [node("a", [], ["o1.md"]), node("a", [], ["o2.md"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "field 'id'" in e and "duplicate" in e for e in errs), errs


def test_orphan_input(write_flow, flow_data):
    flow_data["nodes"][2]["inputs"].append("nowhere/${slug}.md")
    errs = errors_of(write_flow, flow_data, slug="feat")
    assert any(
        "node 'c'" in e and "field 'inputs'" in e and "nowhere/feat.md" in e and "run_inputs" in e
        for e in errs
    ), errs


def test_input_orphan_when_run_inputs_missing(write_flow, flow_data):
    flow_data["run_inputs"] = []
    errs = errors_of(write_flow, flow_data)
    assert any("node 'a'" in e and "field 'inputs'" in e for e in errs), errs


def test_duplicate_output_across_nodes(write_flow, flow_data):
    flow_data["nodes"][2]["outputs"] = ["out/${slug}.a.md"]
    errs = errors_of(write_flow, flow_data)
    assert any(
        "field 'outputs'" in e and "out/s.a.md" in e and "node 'a'" in e and "node 'c'" in e
        for e in errs
    ), errs


def test_duplicate_output_within_same_node(write_flow, node):
    data = {"name": "x", "nodes": [node("a", [], ["o.md", "o.md"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "field 'outputs'" in e and "o.md" in e for e in errs), errs


def test_duplicate_output_after_slug_resolution(write_flow, node):
    data = {"name": "x", "nodes": [node("a", [], ["o/${slug}.md"]), node("b", [], ["o/foo.md"])]}
    assert errors_of(write_flow, data, slug="foo")
    validate_flow(flow_of(write_flow, data, slug="bar"))


def test_two_node_cycle(write_flow, node):
    data = {"name": "x", "nodes": [node("a", ["b.md"], ["a.md"]), node("b", ["a.md"], ["b.md"])]}
    errs = errors_of(write_flow, data)
    cyc = [e for e in errs if "cycle" in e]
    assert cyc and "node 'a'" in cyc[0] and "'b'" in cyc[0], errs


def test_three_node_cycle(write_flow, node):
    data = {
        "name": "x",
        "run_inputs": ["seed.md"],
        "nodes": [
            node("a", ["seed.md", "c.md"], ["a.md"]),
            node("b", ["a.md"], ["b.md"]),
            node("c", ["b.md"], ["c.md"]),
        ],
    }
    errs = errors_of(write_flow, data)
    cyc = [e for e in errs if "cycle" in e]
    assert cyc and all(n in cyc[0] for n in ("'a'", "'b'", "'c'")), errs


def test_self_cycle(write_flow, node):
    data = {"name": "x", "nodes": [node("a", ["a.md"], ["a.md"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "cycle" in e for e in errs), errs


def test_diamond_is_not_a_cycle(write_flow, node):
    data = {
        "name": "x",
        "run_inputs": ["seed.md"],
        "nodes": [
            node("a", ["seed.md"], ["a.md"]),
            node("b", ["a.md"], ["b.md"]),
            node("c", ["a.md"], ["c.md"]),
            node("d", ["b.md", "c.md"], ["d.md"]),
        ],
    }
    validate_flow(flow_of(write_flow, data))


def test_all_problems_reported_together(write_flow, node):
    data = {"name": "x", "nodes": [node("a", ["ghost.md"], ["o.md"]), node("b", [], ["o.md"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "inputs" in e for e in errs)
    assert any("outputs" in e and "node 'b'" in e for e in errs)


def test_execution_order_follows_dependencies(write_flow, node):
    # declarado fora de ordem: c antes de b
    data = {
        "name": "x",
        "run_inputs": ["seed.md"],
        "nodes": [
            node("c", ["b.md"], ["c.md"]),
            node("b", ["a.md"], ["b.md"]),
            node("a", ["seed.md"], ["a.md"]),
        ],
    }
    assert [n.id for n in execution_order(flow_of(write_flow, data))] == ["a", "b", "c"]


def test_execution_order_is_stable_for_independent_nodes(write_flow, node):
    data = {"name": "x", "nodes": [node("z", [], ["z.md"]), node("m", [], ["m.md"]), node("a", [], ["a.md"])]}
    assert [n.id for n in execution_order(flow_of(write_flow, data))] == ["z", "m", "a"]


def test_execution_order_raises_on_cycle(write_flow, node):
    data = {"name": "x", "nodes": [node("a", ["b.md"], ["a.md"]), node("b", ["a.md"], ["b.md"])]}
    with pytest.raises(FlowError, match="cycle"):
        execution_order(flow_of(write_flow, data))


def test_cli_accepts_valid_flow(write_flow, flow_data, capsys):
    from engine.validate import main

    assert main([str(write_flow(flow_data))]) == 0
    assert "OK" in capsys.readouterr().out


def test_cli_rejects_cycle_naming_the_node(write_flow, node, capsys):
    from engine.validate import main

    data = {"name": "x", "nodes": [node("a", ["b.md"], ["a.md"]), node("b", ["a.md"], ["b.md"])]}
    assert main([str(write_flow(data))]) == 1
    err = capsys.readouterr().err
    assert "node 'a'" in err and "cycle" in err


def test_run_input_also_produced_by_a_node(write_flow, node):
    data = {"name": "x", "run_inputs": ["o.md"], "nodes": [node("a", [], ["o.md"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "field 'outputs'" in e and "run_inputs" in e for e in errs), errs


def test_input_only_from_conditional_producer_is_rejected(write_flow, node):
    data = {
        "name": "x",
        "run_inputs": ["seed.md"],
        "nodes": [
            node("review", ["seed.md"], ["review.md"], when="diff_lines > 150"),
            node("commit", ["review.md"], ["commit.md"]),
        ],
    }
    errs = errors_of(write_flow, data)
    assert any(
        "node 'commit'" in e and "field 'inputs'" in e and "node 'review'" in e and "conditional" in e
        for e in errs
    ), errs


def test_conditional_consumer_of_conditional_producer_is_also_rejected(write_flow, node):
    data = {
        "name": "x",
        "run_inputs": ["seed.md"],
        "nodes": [
            node("a", ["seed.md"], ["a.md"], when="sensitive"),
            node("b", ["a.md"], ["b.md"], when="sensitive"),
        ],
    }
    errs = errors_of(write_flow, data)
    assert any("node 'b'" in e and "node 'a'" in e and "conditional" in e for e in errs), errs


def test_conditional_producer_nobody_consumes_is_fine(write_flow, node):
    data = {
        "name": "x",
        "run_inputs": ["seed.md"],
        "nodes": [node("a", ["seed.md"], ["a.md"], when="sensitive"), node("b", ["seed.md"], ["b.md"])],
    }
    validate_flow(flow_of(write_flow, data))


def test_after_unknown_node_id(write_flow, node):
    data = {"name": "x", "nodes": [node("a", [], ["a.md"], after=["ghost"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "field 'after'" in e and "ghost" in e for e in errs), errs


def test_after_orders_nodes_without_data_dependency(write_flow, node):
    data = {
        "name": "x",
        "nodes": [node("commit", [], ["c.md"], after=["review"]), node("review", [], ["r.md"], when="sensitive")],
    }
    assert [n.id for n in execution_order(flow_of(write_flow, data))] == ["review", "commit"]


def test_after_cycle(write_flow, node):
    data = {
        "name": "x",
        "nodes": [node("a", [], ["a.md"], after=["b"]), node("b", [], ["b.md"], after=["a"])],
    }
    errs = errors_of(write_flow, data)
    cyc = [e for e in errs if "cycle" in e]
    assert cyc and "'a'" in cyc[0] and "'b'" in cyc[0], errs


def test_after_self_reference_is_a_cycle(write_flow, node):
    data = {"name": "x", "nodes": [node("a", [], ["a.md"], after=["a"])]}
    errs = errors_of(write_flow, data)
    assert any("node 'a'" in e and "cycle" in e for e in errs), errs


def test_after_mixes_with_data_edges_in_cycle(write_flow, node):
    data = {
        "name": "x",
        "nodes": [node("a", ["b.md"], ["a.md"]), node("b", [], ["b.md"], after=["a"])],
    }
    assert any("cycle" in e for e in errors_of(write_flow, data))
