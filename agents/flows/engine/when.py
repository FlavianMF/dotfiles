"""Parser e avaliador da expressão `when` dos nós.

Gramática (sem `eval`, sem `ast`; só este parser descendente recursivo):

    or_expr    := and_expr ("or" and_expr)*
    and_expr   := primary ("and" primary)*
    primary    := "(" or_expr ")" | comparison
    comparison := operand [("==" | "!=" | "<" | "<=" | ">" | ">=") operand]
    operand    := INT | "true" | "false" | NAME

Variáveis permitidas: `diff_lines` (int) e `sensitive` (bool). Um operando
sozinho só vale se for booleano (ex.: `sensitive`). Os dois lados de uma
comparação têm o mesmo tipo, e `<`, `<=`, `>`, `>=` exigem int.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

WHEN_VARIABLES: dict[str, type] = {"diff_lines": int, "sensitive": bool}

_COMPARATORS = ("==", "!=", "<=", ">=", "<", ">")
_ORDERING = ("<", "<=", ">", ">=")
_MAX_LEN = 500
_MAX_DEPTH = 16


class WhenError(ValueError):
    """Expressão `when` inválida, ou variável ausente/mal tipada na avaliação."""


@dataclass(frozen=True)
class _Operand:
    name: str | None  # nome da variável, ou None para literal
    value: int | bool | None  # valor do literal
    type: type

    def resolve(self, variables: Mapping[str, object]) -> int | bool:
        if self.name is None:
            return self.value  # type: ignore[return-value]
        if self.name not in variables:
            raise WhenError(f"variable '{self.name}' not provided")
        got = variables[self.name]
        if type(got) is not self.type:
            raise WhenError(
                f"variable '{self.name}' must be {self.type.__name__}, got {type(got).__name__}"
            )
        return got  # type: ignore[return-value]


@dataclass(frozen=True)
class _Cmp:
    op: str | None  # None: operando booleano sozinho
    left: _Operand
    right: _Operand | None

    def evaluate(self, variables: Mapping[str, object]) -> bool:
        left = self.left.resolve(variables)
        if self.op is None:
            return bool(left)
        right = self.right.resolve(variables)  # type: ignore[union-attr]
        return {
            "==": left == right,
            "!=": left != right,
            "<": left < right,
            "<=": left <= right,
            ">": left > right,
            ">=": left >= right,
        }[self.op]


@dataclass(frozen=True)
class _Logic:
    op: str  # "and" | "or"
    terms: tuple[_Node, ...]

    def evaluate(self, variables: Mapping[str, object]) -> bool:
        # Sem curto-circuito: uma variável ausente falha sempre, não só no ramo avaliado.
        results = [t.evaluate(variables) for t in self.terms]
        return all(results) if self.op == "and" else any(results)


_Node = _Cmp | _Logic


@dataclass(frozen=True)
class WhenExpr:
    source: str
    root: _Node

    def evaluate(self, variables: Mapping[str, object]) -> bool:
        return self.root.evaluate(variables)


def _tokenize(text: str) -> list[tuple[str, str, int]]:
    tokens: list[tuple[str, str, int]] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif c.isascii() and c.isdigit():
            j = i
            while j < n and text[j].isascii() and text[j].isdigit():
                j += 1
            tokens.append(("int", text[i:j], i))
            i = j
        elif c.isascii() and (c.isalpha() or c == "_"):
            j = i
            while j < n and text[j].isascii() and (text[j].isalnum() or text[j] == "_"):
                j += 1
            tokens.append(("name", text[i:j], i))
            i = j
        elif c in "()":
            tokens.append((c, c, i))
            i += 1
        else:
            for op in _COMPARATORS:
                if text.startswith(op, i):
                    tokens.append(("cmp", op, i))
                    i += len(op)
                    break
            else:
                raise WhenError(f"unexpected character {c!r} at position {i}")
    return tokens


class _Parser:
    def __init__(self, tokens: list[tuple[str, str, int]]) -> None:
        self.tokens = tokens
        self.pos = 0
        self.depth = 0

    def peek(self) -> tuple[str, str, int] | None:
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def next(self) -> tuple[str, str, int]:
        tok = self.peek()
        if tok is None:
            raise WhenError("unexpected end of expression")
        self.pos += 1
        return tok

    def is_keyword(self, word: str) -> bool:
        tok = self.peek()
        return tok is not None and tok[0] == "name" and tok[1] == word

    def parse(self) -> _Node:
        if not self.tokens:
            raise WhenError("empty expression")
        node = self.or_expr()
        tok = self.peek()
        if tok is not None:
            raise WhenError(f"unexpected {tok[1]!r} at position {tok[2]}")
        return node

    def or_expr(self) -> _Node:
        terms = [self.and_expr()]
        while self.is_keyword("or"):
            self.next()
            terms.append(self.and_expr())
        return terms[0] if len(terms) == 1 else _Logic("or", tuple(terms))

    def and_expr(self) -> _Node:
        terms = [self.primary()]
        while self.is_keyword("and"):
            self.next()
            terms.append(self.primary())
        return terms[0] if len(terms) == 1 else _Logic("and", tuple(terms))

    def primary(self) -> _Node:
        tok = self.peek()
        if tok is not None and tok[0] == "(":
            self.next()
            self.depth += 1
            if self.depth > _MAX_DEPTH:
                raise WhenError(f"parentheses nested deeper than {_MAX_DEPTH}")
            node = self.or_expr()
            self.depth -= 1
            closing = self.next()
            if closing[0] != ")":
                raise WhenError(f"expected ')' at position {closing[2]}")
            return node
        return self.comparison()

    def comparison(self) -> _Cmp:
        left = self.operand()
        tok = self.peek()
        if tok is None or tok[0] != "cmp":
            if left.name is None or left.type is not bool:
                raise WhenError(f"{left.name or left.value!r} is not a boolean variable; compare it")
            return _Cmp(None, left, None)
        self.next()
        op = tok[1]
        right = self.operand()
        if left.type is not right.type:
            raise WhenError(
                f"cannot compare {left.type.__name__} with {right.type.__name__} at position {tok[2]}"
            )
        if op in _ORDERING and left.type is not int:
            raise WhenError(f"operator {op!r} needs integers at position {tok[2]}")
        return _Cmp(op, left, right)

    def operand(self) -> _Operand:
        kind, text, pos = self.next()
        if kind == "int":
            return _Operand(None, int(text), int)
        if kind == "name":
            if text in ("true", "false"):
                return _Operand(None, text == "true", bool)
            if text in WHEN_VARIABLES:
                return _Operand(text, None, WHEN_VARIABLES[text])
            if text in ("and", "or"):
                raise WhenError(f"unexpected {text!r} at position {pos}")
            raise WhenError(
                f"unknown variable {text!r} (allowed: {', '.join(sorted(WHEN_VARIABLES))})"
            )
        raise WhenError(f"unexpected {text!r} at position {pos}")


def parse_when(text: str) -> WhenExpr:
    if not isinstance(text, str):
        raise WhenError("expression must be a string")
    if len(text) > _MAX_LEN:
        raise WhenError(f"expression longer than {_MAX_LEN} characters")
    return WhenExpr(text, _Parser(_tokenize(text)).parse())


def evaluate_when(text: str, variables: Mapping[str, object]) -> bool:
    return parse_when(text).evaluate(variables)
