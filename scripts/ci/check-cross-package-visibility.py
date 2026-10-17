#!/usr/bin/env python3
"""Fails when Apex in one package reaches Apex another package cannot share.

Every package shares one namespace (ADR-0017), and a `public` member of one 2GP package is
invisible to another unless it is also `@NamespaceAccessible` (or `global`, which BarnCRM never
uses). Unmanaged deploys see everything, so neither org tests nor deploys catch a missing
annotation: it surfaces only when a module's package version is first built, which compiles
the module's test classes too. This check reads each package's classes, test classes included,
and, for every reference into a package it depends on (sfdx-project.json `dependencies`,
shared `@IsTest` factories included), requires that:

- the class named (`Core.member`, `new Core()`, a type in a declaration) is visible;
- a static member, inner type or member of that inner type reached as `Class.member` or
  `Class.Inner.member` is visible;
- a constructor called with `new Class(...)` or `new Class.Inner(...)` is visible, when the
  type declares constructors;
- a field or method read through a local variable, parameter or field declared with that type
  (`OrgShapeDetector.OrgShape shape; shape.hasNpsp`), or through a static call's result
  (`OrgShapeDetector.detect().hasNpsp`), is visible.

A `@TestVisible private` member counts as not visible: `@TestVisible` does not cross a package
boundary, so a module test needs a `@NamespaceAccessible` seam (`TriggerHandler.setTestRecords`).

It is token based, not a compiler: longer call chains, inherited members called without a
qualifier, and overloads (any visible overload passes) are not resolved, and a member it cannot
find is skipped. A false positive goes in
cross-package-visibility-allowlist.txt as `ReferencingClass Target: reason`; an entry that no
longer matches anything fails the check, so the list cannot go stale.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apex_visibility as av  # noqa: E402

ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cross-package-visibility-allowlist.txt")


def _line(text, pos):
    return text.count("\n", 0, pos) + 1


def _member_targets(index, owner, name, called=True):
    """[(target, visible)] for a name looked up in a type: members and inner types.

    Apex names ignore case, so `JobNotifier.Notice` (a type) and `notice(...)` (a method) share
    a key; a name not followed by `(` is the type when there is one.
    """
    out = []
    for entry in owner.members.get(name.lower(), []):
        if isinstance(entry, av.Type):
            out.append((entry.qualified, entry.visible(), entry))
    if out and not called:
        return out
    members = [m for m in owner.members.get(name.lower(), []) if isinstance(m, av.Member)]
    if members:
        ok = any(av.member_visible(owner, m) for m in members)
        out.append((f"{owner.qualified}.{members[0].name}", ok, None))
    return out


def _returned_type(index, owner, method):
    """The indexed type a method returns: an inner type of its class, or a top-level class."""
    if not isinstance(method, av.Member) or method.kind != "method" or not method.type_ref:
        return None
    name = method.type_ref
    if "<" in name or "[" in name:
        return None
    if "." not in name:
        inner = [t for t in owner.members.get(name.lower(), []) if isinstance(t, av.Type)]
        if inner:
            return inner[0]
    return index.find(name)


def _ctor_ok(t):
    return not t.ctors or any(av.member_visible(t, c) for c in t.ctors)


def references(index, name):
    """[(line, target, visible)] for every cross-package reference in one production class."""
    me = index.types[name]
    text = index.text[name]
    deps = index.deps.get(me.package, set())
    found = []
    for cname, target in index.types.items():
        if target.package not in deps:
            continue
        if any(isinstance(t, av.Type) for t in me.members.get(cname.lower(), [])):
            continue  # the class's own inner type of that name shadows the other package's

        pattern = r"(?<![\w.])" + re.escape(cname) + r"\b"
        first = re.search(pattern, text)
        if not first:
            continue
        found.append((_line(text, first.start()), target.qualified, target.visible()))
        # Class.member and Class.Inner.member
        for m in re.finditer(pattern + r"\s*\.\s*(\w+)(?:\s*\.\s*(\w+))?", text):
            called = text[m.end(1) :].lstrip().startswith("(")
            for qualified, ok, inner in _member_targets(index, target, m.group(1), called):
                found.append((_line(text, m.start()), qualified, ok))
                if inner is not None and m.group(2):
                    for q2, ok2, _ in _member_targets(index, inner, m.group(2)):
                        found.append((_line(text, m.start()), q2, ok2))
        # Class.method(...).member: the member of the type the method returns
        for m in re.finditer(pattern + r"\s*\.\s*(\w+)\s*\([^()]*\)\s*\.\s*(\w+)", text):
            for method in target.members.get(m.group(1).lower(), []):
                returned = _returned_type(index, target, method)
                if returned is not None:
                    for qualified, ok, _ in _member_targets(index, returned, m.group(2)):
                        found.append((_line(text, m.start()), qualified, ok))
        # Constructors
        for m in re.finditer(r"\bnew\s+" + re.escape(cname) + r"\s*(?:\.\s*(\w+)\s*)?\(", text):
            t = index.find(f"{cname}.{m.group(1)}") if m.group(1) else target
            if t is not None and not _ctor_ok(t):
                found.append((_line(text, m.start()), f"{t.qualified}()", False))
        # Variables declared with the type: Class x, Class.Inner x
        decl = re.compile(pattern + r"(?:\s*\.\s*(\w+))?\s+(\w+)\s*(?=[=;,):])")
        for m in decl.finditer(text):
            t = index.find(f"{cname}.{m.group(1)}") if m.group(1) else target
            var = m.group(2)
            if t is None or var.lower() in av.NOT_TYPES:
                continue
            for use in re.finditer(r"(?<![\w.])" + re.escape(var) + r"\s*\.\s*(\w+)", text):
                for qualified, ok, _ in _member_targets(index, t, use.group(1)):
                    found.append((_line(text, use.start()), qualified, ok))
    return found


def violations(index):
    """{(referencing class, target): (path, line)} for every reference that is not visible."""
    out = {}
    for name, me in sorted(index.types.items()):
        if not index.deps.get(me.package):
            continue
        for line, target, ok in references(index, name):
            if not ok and (name, target) not in out:
                out[(name, target)] = (me.path, line)
    return out


def main():
    index = av.load(".")
    allowed, errors = av.read_allowlist(ALLOWLIST)
    found = violations(index)
    failures = list(errors)
    for (name, target), (path, line) in sorted(found.items(), key=lambda kv: (kv[1], kv[0])):
        if (name, target) in allowed:
            continue
        failures.append(
            f"{path}:{line}: {name} reaches {target} in another package, which is not "
            "@NamespaceAccessible (or global)"
        )
    for (name, target), n in sorted(allowed.items(), key=lambda kv: kv[1]):
        if (name, target) not in found:
            failures.append(f"{os.path.basename(ALLOWLIST)}:{n}: '{name} {target}' matches nothing; remove it")
    for f in failures:
        print(f)
    if failures:
        print(
            f"{len(failures)} problem(s). Annotate the member @NamespaceAccessible (ADR-0017), "
            "or add a reasoned allowlist entry for a false positive."
        )
        return 1
    scanned = sum(1 for t in index.types.values() if index.deps.get(t.package))
    print(f"Every cross-package reference in {scanned} module classes is @NamespaceAccessible.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
