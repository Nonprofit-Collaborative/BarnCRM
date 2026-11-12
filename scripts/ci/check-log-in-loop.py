#!/usr/bin/env python3
"""Flags an Error Log call made once per failed row of a partial save (R-E7, plan D-200 P4).

A loop over the results of a partial save (`Database.SaveResult`, `DeleteResult` or
`UpsertResult`) that calls `ErrorLogger.log*(` inside it publishes one Error Log event per
failed row: a bulk load that fails 10,000 rows writes 10,000 entries and spends one immediate
publish each. Collect the failures and log them once after the loop, with
`ErrorLogger.logFailures` or `logMessages` (one statement, one entry per row) or one summary
`logMessage`.

A loop is over results when its header names a result type (`for (Database.SaveResult result
: results)`), or when its condition reads `.size()` of, or its body indexes, a variable the
class declares as a list or array of one of the result types. A call that has to stay in its loop is listed in
`scripts/ci/log-in-loop-allowlist.txt` as `ClassName.methodName` with the reason after ` # `.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import is_test_class, strip  # noqa: E402

ALLOWLIST = "scripts/ci/log-in-loop-allowlist.txt"
RESULT = r"Database\s*\.\s*(?:Save|Delete|Upsert|Undelete)Result"
DECLARED = re.compile(
    r"(?:List\s*<\s*" + RESULT + r"\s*>|" + RESULT + r"\s*\[\s*\])\s+(\w+)\s*[=;,)]"
)
FOR_HEADER = re.compile(r"\bfor\s*\(")
# ErrorLogger's own methods, and a class's own `log...(` helper, which wraps one.
LOG_CALL = re.compile(r"(?:\bErrorLogger\s*\.\s*|(?<![.\w]))log\w*\s*\(")
METHOD = re.compile(
    r"\b(?:public|private|protected|global|static|override|virtual)\b[^;{}=]*?\b(\w+)\s*\([^;{}]*\)\s*\{"
)


def matching(text, start, opening, closing):
    """The index just past the bracket that closes the one at `start`."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opening:
            depth += 1
        elif text[i] == closing:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def loop_body(text, header_end):
    """The loop's body: a braced block, or the one statement up to its semicolon."""
    i = header_end
    while i < len(text) and text[i].isspace():
        i += 1
    if i < len(text) and text[i] == "{":
        return i, matching(text, i, "{", "}")
    end = text.find(";", i)
    return i, len(text) if end < 0 else end + 1


def over_results(header, body, result_names):
    """A loop over results: typed by a result type, bounded by one's size, or indexing one."""
    if re.search(RESULT, header):
        return True
    return any(
        re.search(r"\b" + re.escape(name) + r"\s*\.\s*size\s*\(", header)
        or re.search(r"\b" + re.escape(name) + r"\s*\[", body)
        for name in result_names
    )


def method_at(text, position):
    name = None
    for match in METHOD.finditer(text, 0, position):
        name = match.group(1)
    return name or "?"


def findings(path, source):
    text = strip(source)
    names = set(DECLARED.findall(text))
    cls = os.path.basename(path)[: -len(".cls")]
    found = {}
    for header in FOR_HEADER.finditer(text):
        open_paren = header.end() - 1
        close_paren = matching(text, open_paren, "(", ")")
        start, end = loop_body(text, close_paren)
        if not over_results(text[open_paren:close_paren], text[start:end], names):
            continue
        for call in LOG_CALL.finditer(text, start, end):
            line = text.count("\n", 0, call.start()) + 1
            key = f"{cls}.{method_at(text, header.start())}"
            found.setdefault((key, line), path)
    return found


def main():
    allowed = set()
    if os.path.exists(ALLOWLIST):
        with open(ALLOWLIST, encoding="utf-8") as handle:
            for raw in handle:
                entry = raw.split(" # ")[0].strip()
                if entry and not entry.startswith("#"):
                    if " # " not in raw:
                        print(f"{ALLOWLIST}: '{entry}' has no reason after ' # '")
                        return 1
                    allowed.add(entry)
    problems, used = [], set()
    for path in sorted(glob.glob("packages/*/main/default/classes/*.cls")):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        if is_test_class(source):
            continue
        for (key, line), where in sorted(findings(path, source).items()):
            if key in allowed:
                used.add(key)
                continue
            problems.append(
                f"{where}:{line}: {key} calls ErrorLogger inside a loop over save results;"
                " collect the failures and log once after the loop (ErrorLogger.logFailures)"
            )
    problems += [f"{ALLOWLIST}: '{key}' no longer has a log call in such a loop; remove it"
                 for key in sorted(allowed - used)]
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-log-in-loop.py: FAILED, {len(problems)} problem(s)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
