#!/usr/bin/env python3
"""Fails when a global or @NamespaceAccessible Apex signature disappears or changes.

In a managed package a `global` signature can never be removed or changed once a version is
promoted, and an `@NamespaceAccessible` one is what every other BarnCRM package compiles
against: an installed module built against an older Core breaks when Core drops one (D-199,
D-200 N8). So every such signature in packaged Apex is listed in a committed snapshot,
scripts/ci/api-surface.txt, one `<package>/<file> | <signature>` line each, and:

- a snapshot line with no match in the source fails: the signature was removed or changed.
  The rule is "deprecate for one release, never remove" (docs/contributor-guide/ci.md,
  "Global and namespace-accessible API"); mark it `@Deprecated` and keep it.
- a signature in the source that the snapshot lacks fails too, so the snapshot stays the
  whole surface. `--update` adds it (and only adds: it refuses while anything was removed).

A signature is the declaration with annotations, parameter names and initial values left
out, whitespace collapsed: `public static Map<String,Object> runHealthCheck()`. Renaming a
parameter is not a change; changing its type is. Test classes are not packaged API and are
skipped.

    python3 scripts/ci/check-api-surface.py [--update]
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, strip  # noqa: E402

SNAPSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "api-surface.txt")
HEADER = (
    "# Global and @NamespaceAccessible Apex signatures (scripts/ci/check-api-surface.py).\n"
    "# Never remove or change a line: deprecate for one release instead. Add with --update.\n"
)
ANNOTATION = re.compile(r"@\w+(\s*\([^()]*\))?\s*")
MODIFIERS = {"global", "public", "private", "protected", "static", "final", "virtual", "abstract",
             "override", "transient", "webservice", "with", "without", "inherited", "sharing"}


def split_top(text, sep=","):
    """Split on sep outside <> and () nesting."""
    parts, depth, cur = [], 0, []
    for c in text:
        if c in "<(":
            depth += 1
        elif c in ">)":
            depth -= 1
        if c == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def drop_name(param):
    """'final Map<String, Object> values' -> 'Map<String,Object>'."""
    words = split_top(param, " ")
    words = [w for w in words if w != "final"]
    return re.sub(r"\s+", "", " ".join(words[:-1]) if len(words) > 1 else param)


def normalize(header):
    header = ANNOTATION.sub("", header)
    header = re.sub(r"\s+", " ", header).strip()
    kind = re.search(r"\b(class|interface|enum)\s+(\w+)", header)
    if kind and "(" not in header[: kind.start()]:
        # A type: its access, virtual or abstract, kind and name. Sharing, extends and
        # implements can change without breaking a caller.
        mods = [w for w in header[: kind.start()].split() if w in ("global", "public", "virtual", "abstract")]
        return " ".join(mods + [kind.group(1), kind.group(2)])
    paren = header.find("(")
    if paren >= 0 and not re.search(r"\b(class|interface|enum)\b", header[:paren]):
        close = header.rfind(")")
        params = ",".join(drop_name(p) for p in split_top(header[paren + 1:close]))
        head = re.sub(r"\s*<\s*", "<", re.sub(r"\s*,\s*", ",", re.sub(r"\s*>", ">", header[:paren])))
        return f"{head.strip()}({params})"
    header = re.sub(r"\s*,\s*", ",", header)
    return re.sub(r"\s*<\s*", "<", re.sub(r"\s*>", ">", header))


def signatures(text):
    """The global or @NamespaceAccessible declarations in one class's stripped source."""
    found = []
    for m in re.finditer(r"@NamespaceAccessible\b|(?<![\w.@])global\b", text):
        start = m.start()
        # A declaration starting after annotations: take everything up to its body or value.
        i, depth = start, 0
        while i < len(text):
            c = text[i]
            if c in "(<":
                depth += 1
            elif c in ")>":
                depth -= 1
            elif depth == 0 and c in "{;=":
                break
            i += 1
        header = text[start:i]
        if m.group(0) == "global":
            before = text[max(0, start - 200):start]
            if re.search(r"@NamespaceAccessible\b[^;{}]*$", before):
                continue  # counted from its annotation
        sig = normalize(header)
        words = sig.split("(")[0].split()
        if len([w for w in words if w not in MODIFIERS]) >= 1 and sig not in ("", "global"):
            found.append(sig)
    return found


def current(root="."):
    lines = []
    for path in sorted(glob.glob(os.path.join(root, "packages/*/main/**/*.cls"), recursive=True)):
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
        if is_test_class(raw):
            continue
        rel = os.path.relpath(path, root).replace(os.sep, "/").split("/")
        name = f"{rel[1]}/{rel[-1]}"
        lines += [f"{name} | {sig}" for sig in signatures(strip(raw))]
    return lines


def read_snapshot():
    if not os.path.exists(SNAPSHOT):
        return []
    with open(SNAPSHOT, encoding="utf-8") as handle:
        return [line.rstrip("\n") for line in handle if line.strip() and not line.startswith("#")]


def diff(old, new):
    """(removed, added) as multiset differences."""
    left, right = list(old), list(new)
    removed = []
    for line in old:
        if line in right:
            right.remove(line)
        else:
            removed.append(line)
    return removed, right


def main(argv):
    update = "--update" in argv
    now = current()
    removed, added = diff(read_snapshot(), now)
    for line in removed:
        print(f"REMOVED OR CHANGED: {line}")
    if removed:
        print(f"{len(removed)} signature(s) gone. Keep them (deprecate for one release, never remove); "
              "see the docstring.")
        return 1
    if added and not update:
        for line in added:
            print(f"NEW: {line}")
        print(f"{len(added)} new signature(s) not in {os.path.relpath(SNAPSHOT)}. Run with --update "
              "and commit it; each one is permanent once a version is promoted.")
        return 1
    if update and added:
        with open(SNAPSHOT, "w", encoding="utf-8") as handle:
            handle.write(HEADER + "".join(line + "\n" for line in sorted(now)))
        print(f"Added {len(added)} signature(s) to {os.path.relpath(SNAPSHOT)}.")
        return 0
    print(f"API surface unchanged: {len(now)} global and @NamespaceAccessible signatures.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
