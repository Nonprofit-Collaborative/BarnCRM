#!/usr/bin/env python3
"""Fails when a class built by name across a package boundary cannot be built there.

Core builds module classes from strings with NamespaceUtil.resolveType / Type.forName and
newInstance(): trigger handlers named in Automation_Registry__mdt.Handler_Class__c (built by
TriggerDispatcher), and extensions, providers and processors named in a resolver's string
constants (HealthCheckExtensions, NightlyJobs, SampleDataModules and the rest). Once the
packages are namespaced, a class Core cannot see is skipped at runtime with only an error log
entry: nothing fails at deploy or package version creation. So every class named this way that
lives in another package than the code resolving it must be:

- `@NamespaceAccessible` and `public` (or `global`), and
- declare a no-argument constructor that is itself `@NamespaceAccessible` and `public` (or
  `global`). The implicit constructor is not accepted, as docs/contributor-guide/dynamic-apex.md
  and ADR-0017 ask for an explicit one.

Names come from every Automation_Registry__mdt record (resolved by Core) and from the string
literals in PRODUCTION classes that call resolveType or Type.forName (test classes are skipped
for now) whose value is the name of a class in another package. Same-package lookups (Core's own
handlers, Giving's receipt renderers) need nothing and are not checked.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apex_visibility as av  # noqa: E402

RESOLVER_PACKAGE = "core"  # TriggerDispatcher, which builds every registered handler
RESOLVES = re.compile(r"\bresolveType\s*\(|\bType\s*\.\s*forName\s*\(", re.I)


def named_classes(index, handlers):
    """[(where, resolver package, class name)] for every class named as a string."""
    out = [(path, RESOLVER_PACKAGE, name) for path, name in handlers]
    for name, me in sorted(index.types.items()):
        text = index.text[name]
        if me.is_test or not RESOLVES.search(text):
            continue
        raw = index.raw[name]
        for start, value in literals(raw, text):
            value = value.strip()
            if re.fullmatch(r"\w+(?:\.\w+)?", value) and index.find(value) is not None:
                out.append((f"{me.path}:{raw.count(chr(10), 0, start) + 1}", me.package, value))
    return out


def literals(raw, text):
    """[(offset, value)] for each string literal outside comments.

    apex_source.strip keeps offsets and turns each literal into '' followed by spaces, so a
    literal starts wherever the stripped text has '' and the raw text has a quote.
    """
    out, i = [], text.find("''")
    while i >= 0:
        j = i + 1
        while j < len(raw) and raw[j] != "'":
            j += 2 if raw[j] == "\\" else 1
        out.append((i, raw[i + 1 : j]))
        i = text.find("''", j + 1)
    return out


def problems(index, handlers):
    """[(where, message)] for each class built by name in another package that cannot be built."""
    out, seen = [], set()
    for where, resolver, name in named_classes(index, handlers):
        t = index.find(name)
        if t is None:
            continue  # check-custom-metadata.py owns registry names that match no class
        if t.package == resolver or (where, name) in seen:
            continue
        seen.add((where, name))
        missing = []
        if not t.visible():
            missing.append("the class is not @NamespaceAccessible")
        if not any(c.no_arg and av.member_visible(t, c) for c in t.ctors):
            missing.append("it has no @NamespaceAccessible public no-argument constructor")
        if missing:
            out.append((where, f"{t.qualified} ({t.path}) is built by name from {resolver}, but " + " and ".join(missing)))
    return out


def main():
    index = av.load(".")
    found = problems(index, av.registry_handlers("."))
    for where, message in found:
        print(f"{where}: {message}")
    if found:
        print(
            f"{len(found)} class(es) another package builds by name would be skipped once namespaced. "
            "Add @NamespaceAccessible to the class and a @NamespaceAccessible public no-argument "
            "constructor (see GiftSoftCreditHandler)."
        )
        return 1
    print("Every class built by name across a package boundary is @NamespaceAccessible with an accessible constructor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
