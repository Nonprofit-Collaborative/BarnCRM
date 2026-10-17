#!/usr/bin/env python3
"""Fails if a field, property or method carries both @AuraEnabled and @NamespaceAccessible.

The platform rejects the pair at deploy time ("AuraEnabled fields cannot be
NamespaceAccessible", "AuraEnabled methods cannot be NamespaceAccessible"), and an offline check
never shows it. Drop @NamespaceAccessible and, if another package needs the member, add a
@NamespaceAccessible getter or wrapper method that is not @AuraEnabled (HealthCheckService
`Finding.getKey`, SettingsController `save`).
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

SOURCES = ["packages/*/main/**/*.cls"]
ANNOTATIONS = re.compile(r"((?:\s*@\w+(?:\([^)]*\))?)+)\s*([^;={}(]*)([;={}(])")


def check_text(raw):
    """Return (line, message) pairs for members carrying both annotations."""
    text = strip(raw)
    problems = []
    for m in ANNOTATIONS.finditer(text):
        names = {n.lower() for n in re.findall(r"@(\w+)", m.group(1))}
        if not {"auraenabled", "namespaceaccessible"} <= names:
            continue
        head = m.group(2)
        if re.search(r"\b(class|interface|enum)\b", head):
            continue
        line = text.count("\n", 0, m.start(2)) + 1
        problems.append((line, f"'{head.strip()}' is @AuraEnabled and @NamespaceAccessible"))
    return problems


def main():
    files = sorted({f for pattern in SOURCES for f in glob.glob(pattern, recursive=True)})
    total = 0
    for f in files:
        for line, message in check_text(open(f, encoding="utf-8").read()):
            print(f"{f}:{line}: {message}")
            total += 1
    if total:
        print(f"{total} member(s) rejected by the platform: remove @NamespaceAccessible or use an accessor method.")
        return 1
    print(f"No @AuraEnabled member in {len(files)} packaged Apex files is @NamespaceAccessible.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
