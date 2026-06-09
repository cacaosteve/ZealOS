#!/usr/bin/env python3
"""Small compatibility checks for the ExodusTrail ZealC prototype.

This is not a ZealC compiler. It catches patterns that have already caused
interactive ZealOS compile failures while this prototype is being iterated.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


DEFAULT_FILE = Path(__file__).resolve().parents[1] / "src/Demo/Games/ExodusTrail.ZC"

CHECKS = (
    (re.compile(r"\|\|"), "avoid ||; split into two if statements"),
    (re.compile(r"&&"), "avoid &&; split into nested if statements"),
    (re.compile(r"FileWrite\([^;\n]*\([A-Za-z0-9_]+\s*\*\)"), "avoid inline casts inside FileWrite"),
    (re.compile(r"#include\s+\"\"\s*$"), "empty #include is a command typo"),
    (re.compile(r"^\s*ExodusTrail;\s*$"), "do not auto-run from the library file; use Apps/ExodusTrail/Run.ZC"),
    (re.compile(r"^\s*U8\s*\*\s*[A-Za-z_][A-Za-z0-9_]*\s*\[[^]]+\]\s*="), "avoid global initialized string pointer arrays; use a switch helper"),
)


FUNC_RE = re.compile(
    r"(?m)^\s*(?:U0|Bool|I64|U8\s*\*|ETGame\s*\*)\s*"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*\{"
)


def _param_names(params: str) -> list[str]:
    names: list[str] = []
    for raw in params.split(","):
        raw = raw.strip()
        if not raw or raw == "void":
            continue
        raw = raw.split("=", 1)[0].strip()
        match = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^]]*\])?$", raw)
        if match:
            names.append(match.group(1))
    return names


def _matching_brace(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    escaped = False

    for i in range(open_index, len(text)):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def unused_parameter_errors(path: Path, text: str) -> list[str]:
    errors: list[str] = []
    for match in FUNC_RE.finditer(text):
        params = _param_names(match.group(2))
        if not params:
            continue

        close = _matching_brace(text, match.end() - 1)
        if close < 0:
            continue

        body = text[match.end():close]
        line_no = text.count("\n", 0, match.start()) + 1
        for param in params:
            if not re.search(rf"\b{re.escape(param)}\b", body):
                errors.append(
                    f"{path}:{line_no}: parameter '{param}' is never used in "
                    f"{match.group(1)}(); ZealC warns on unused variables"
                )
    return errors


def undefined_local_call_errors(path: Path, text: str) -> list[str]:
    errors: list[str] = []
    defined = {match.group(1) for match in FUNC_RE.finditer(text)}

    for match in re.finditer(r"\b(ET[A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
        name = match.group(1)
        line = text.count("\n", 0, match.start()) + 1
        line_text = text.splitlines()[line - 1]

        if re.match(r"\s*(?:U0|Bool|I64|U8\s*\*|ETGame\s*\*)\s*" + re.escape(name) + r"\s*\(", line_text):
            continue
        if name not in defined:
            errors.append(f"{path}:{line}: local call to undefined helper {name}()")

    return errors


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_FILE
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []

    for line_no, line in enumerate(text.splitlines(), 1):
        for pattern, message in CHECKS:
            if pattern.search(line):
                errors.append(f"{path}:{line_no}: {message}: {line.strip()}")
        try:
            line.encode("ascii")
        except UnicodeEncodeError:
            errors.append(f"{path}:{line_no}: non-ASCII text may confuse old tooling")

    errors.extend(unused_parameter_errors(path, text))
    errors.extend(undefined_local_call_errors(path, text))

    if errors:
        print("\n".join(errors))
        return 1

    print(f"{path}: compatibility checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
