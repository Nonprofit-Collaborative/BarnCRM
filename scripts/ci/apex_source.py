"""Shared Apex source helpers for the static CI checks.

One copy of the comment and string stripper, so a fix to it (for example an Apex string
escape) reaches every check that reads Apex: check-apex-access-modes.py,
check-tests-run-as.py and check-person-account-fields.py.
"""

import re


def strip(source):
    """Blank out comments and string literals, keeping offsets and line numbers.

    A string literal becomes '' followed by spaces, so code that looks for a string argument
    still sees one; its contents never match a pattern.
    """
    out = []
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if source.startswith("//", i):
            j = source.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif source.startswith("/*", i):
            j = source.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", source[i:j]))
            i = j
        elif c == "'":
            j = i + 1
            while j < n and source[j] != "'":
                j += 2 if source[j] == "\\" else 1
            out.append("''" + " " * max(0, j - i - 1))
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)
