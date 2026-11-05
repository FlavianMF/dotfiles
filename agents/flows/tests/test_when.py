import pytest

from engine.when import WHEN_VARIABLES, WhenError, evaluate_when, parse_when


@pytest.mark.parametrize(
    ("text", "variables", "expected"),
    [
        ("diff_lines > 150", {"diff_lines": 200, "sensitive": False}, True),
        ("diff_lines > 150", {"diff_lines": 150, "sensitive": False}, False),
        ("diff_lines >= 150", {"diff_lines": 150, "sensitive": False}, True),
        ("diff_lines < 10", {"diff_lines": 3, "sensitive": False}, True),
        ("diff_lines <= 10", {"diff_lines": 11, "sensitive": False}, False),
        ("diff_lines == 7", {"diff_lines": 7, "sensitive": False}, True),
        ("diff_lines != 7", {"diff_lines": 7, "sensitive": False}, False),
        ("150 < diff_lines", {"diff_lines": 151, "sensitive": False}, True),
        ("sensitive", {"diff_lines": 0, "sensitive": True}, True),
        ("sensitive == true", {"diff_lines": 0, "sensitive": True}, True),
        ("sensitive == false", {"diff_lines": 0, "sensitive": True}, False),
        ("sensitive != true", {"diff_lines": 0, "sensitive": False}, True),
        ("diff_lines > 150 or sensitive", {"diff_lines": 10, "sensitive": True}, True),
        ("diff_lines > 150 or sensitive", {"diff_lines": 10, "sensitive": False}, False),
        ("diff_lines > 5 and sensitive", {"diff_lines": 10, "sensitive": False}, False),
        ("diff_lines > 5 and sensitive", {"diff_lines": 10, "sensitive": True}, True),
        # "and" binds tighter than "or"
        ("sensitive or diff_lines > 10 and diff_lines < 5", {"diff_lines": 7, "sensitive": True}, True),
        # parentheses override precedence
        ("(sensitive or diff_lines > 10) and diff_lines < 5", {"diff_lines": 7, "sensitive": True}, False),
        ("  diff_lines>150  ", {"diff_lines": 151, "sensitive": False}, True),
    ],
)
def test_evaluate(text, variables, expected):
    assert evaluate_when(text, variables) is expected


@pytest.mark.parametrize(
    "text",
    [
        "",
        "   ",
        "foo > 1",
        "__import__('os').system('id')",
        "diff_lines.real > 1",
        "diff_lines > 'a'",
        "diff_lines + 1 > 2",
        "diff_lines >",
        "> 1",
        "diff_lines > 1 2",
        "diff_lines > 1 > 0",
        "diff_lines",
        "diff_lines > true",
        "sensitive > 1",
        "sensitive == 1",
        "true",
        "(diff_lines > 1",
        "diff_lines > 1)",
        "()",
        "diff_lines > 1 and",
        "or sensitive",
        "diff_lines > 1 && sensitive",
        "not sensitive",
        "1 if sensitive else 2",
        "diff_lines > 99999999999999999999999999999 or ;",
    ],
)
def test_rejects_invalid(text):
    with pytest.raises(WhenError):
        parse_when(text)


def test_missing_variable_at_evaluation():
    with pytest.raises(WhenError, match="diff_lines"):
        evaluate_when("diff_lines > 1", {"sensitive": True})


def test_wrong_variable_type_at_evaluation():
    with pytest.raises(WhenError, match="sensitive"):
        evaluate_when("sensitive", {"diff_lines": 1, "sensitive": 1})
    with pytest.raises(WhenError, match="diff_lines"):
        evaluate_when("diff_lines > 1", {"diff_lines": True, "sensitive": False})


def test_variables_are_the_documented_ones():
    assert set(WHEN_VARIABLES) == {"diff_lines", "sensitive"}


def test_never_uses_eval_or_exec(monkeypatch):
    import builtins

    def boom(*_a, **_k):
        raise AssertionError("eval/exec must not be used")

    monkeypatch.setattr(builtins, "eval", boom)
    monkeypatch.setattr(builtins, "exec", boom)
    assert evaluate_when("diff_lines > 1 or sensitive", {"diff_lines": 2, "sensitive": False})
    with pytest.raises(WhenError):
        parse_when("__import__('os')")
