#!/usr/bin/env python3
"""Update tests/INVENTORY.md from the docstrings in tests/ and the FS-UAE
scenarios in tests/integration/scenarios.yaml.

Reads the sources with ast and the scenarios with a line parser, so it needs
neither vasm, amitools nor PyYAML.
Run: make test-list-update
"""

import ast
import re
from pathlib import Path

TESTS = Path(__file__).resolve().parent
INVENTORY = TESTS / "INVENTORY.md"
BEGIN, END = "<!-- TESTS:BEGIN -->", "<!-- TESTS:END -->"
TOOLING = ("toolchain.py", "deps.py", "list_tests.py", "prefsrig.py")
SCENARIOS = TESTS / "integration" / "scenarios.yaml"


def cell(text):
    """One markdown table cell: single line, pipes escaped."""
    return " ".join((text or "").split()).replace("|", r"\|")


def summary(doc):
    """The first paragraph of a docstring, as one line."""
    return cell((doc or "").split("\n\n")[0])


def status(doc):
    """The word after 'Status:' in a module docstring, or '' when it has none."""
    for line in (doc or "").splitlines():
        if line.startswith("Status:"):
            rest = line[len("Status:") :].strip()
            return re.split(r"[,.]", rest)[0].strip()
    return ""


def modules():
    for path in sorted(TESTS.glob("*.py")):
        if path.name in TOOLING:
            continue
        yield path, ast.parse(path.read_text())


def scenarios():
    """{section: {name: {key: value}}} for the scenarios and planned sections
    of scenarios.yaml; their entries hold one-line values."""
    out, section, name = {}, None, None
    for line in SCENARIOS.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        key, _, value = line.strip().partition(":")
        if indent == 0:
            section = out.setdefault(key, {}) if key in ("scenarios", "planned") else None
        elif section is not None and indent == 2:
            name = key
            section[name] = {}
        elif section is not None and indent == 4:
            section[name][key] = value.strip().strip('"')
    return out


def render():
    out = [BEGIN, ""]
    out += ["| script | status | what it checks |", "|---|---|---|"]
    for path, tree in modules():
        doc = ast.get_docstring(tree)
        out += ["| `%s` | %s | %s |" % (path.name, status(doc) or "-", summary(doc))]
    sc = scenarios()
    out += [
        "",
        "### FS-UAE integration scenarios",
        "",
        "Run by `make test-integration` from `integration/scenarios.yaml`; "
        "[integration/README.md](integration/README.md) describes the suite. "
        "`planned` scenarios are not implemented yet.",
        "",
        "| scenario | status | what it checks |",
        "|---|---|---|",
    ]
    out += [
        "| `%s` | integration | %s |" % (n, cell(s.get("doc")))
        for n, s in sc.get("scenarios", {}).items()
    ]
    out += [
        "| `%s` | planned | %s. Needs %s. |" % (n, cell(s.get("doc")), cell(s.get("needs")))
        for n, s in sc.get("planned", {}).items()
    ]
    out += ["", END]
    return "\n".join(out) + "\n"


def update():
    text = INVENTORY.read_text()
    head, _, rest = text.partition(BEGIN)
    _, _, tail = rest.partition(END)
    INVENTORY.write_text(head + render().strip() + tail)


if __name__ == "__main__":
    update()
