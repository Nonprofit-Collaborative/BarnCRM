"""Shared Apex declaration index for the cross-package visibility checks.

Used by check-cross-package-visibility.py and check-dynamic-class-visibility.py. It reads every
packaged Apex class, records which package owns it, and records each type and member with its
annotations and modifiers, so a check can ask whether another package of the same namespace can
see it (ADR-0017: `global`, or `public` plus `@NamespaceAccessible`).

This is a token-level reader, not an Apex compiler. It finds a member only when the declaration
starts with at least one modifier; anything it cannot find is treated as unknown, never as a
problem, so its mistakes are missed findings rather than false failures. Running it as a script
does nothing.
"""

import glob
import json
import os
import re
import sys
from xml.etree import ElementTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

MOD = (
    r"(?:public|private|protected|global|static|final|virtual|abstract|override|transient|"
    r"webservice|testmethod|with\s+sharing|without\s+sharing|inherited\s+sharing)"
)
ANN = r"(?:@\w+(?:\s*\([^()]*\))?\s*)*"
TYPE_DECL = re.compile(r"(?<![\w.@])(" + ANN + r")((?:" + MOD + r"\s+)*)(class|interface|enum)\s+(\w+)", re.I)
TYPE_REF = r"[\w.]+(?:\s*<[\w\s.,<>\[\]]*>)?(?:\s*\[\s*\])?"
MEMBER_DECL = re.compile(
    r"(?<![\w.@])(" + ANN + r")((?:" + MOD + r"\s+)+)(?:(" + TYPE_REF + r")\s+)?(\w+)\s*([(=;{,])", re.I
)
NOT_TYPES = {"class", "interface", "enum", "new", "return", "else"}


class Type:
    """One class, interface or enum, top level or inner."""

    def __init__(self, name, outer, package, path, annots, mods, kind, line):
        self.name = name
        self.outer = outer
        self.package = package
        self.path = path
        self.annots = annots
        self.mods = mods
        self.kind = kind
        self.line = line
        self.members = {}
        self.ctors = []

    @property
    def qualified(self):
        return f"{self.outer.name}.{self.name}" if self.outer else self.name

    @property
    def is_test(self):
        top = self.outer or self
        return "istest" in top.annots

    def visible(self):
        """Whether another package can see this type (and its outer type)."""
        if self.outer is not None and not self.outer.visible():
            return False
        return is_visible(self.annots, self.mods)


class Member:
    def __init__(self, name, kind, annots, mods, line, no_arg=False, type_ref=None):
        self.name = name
        self.type_ref = type_ref
        self.kind = kind
        self.annots = annots
        self.mods = mods
        self.line = line
        self.no_arg = no_arg


def is_visible(annots, mods):
    return "global" in mods or ("public" in mods and "namespaceaccessible" in annots)


def member_visible(owner, member):
    """Members of an interface or enum take the type's own visibility."""
    if owner.kind in ("interface", "enum"):
        return owner.visible()
    return owner.visible() and is_visible(member.annots, member.mods)


def _words(text):
    return {w.lower() for w in re.findall(r"\w+", text)}


def _annots(text):
    return {a.lower() for a in re.findall(r"@(\w+)", text)}


def _depths(text):
    depths, depth = [], 0
    for c in text:
        depths.append(depth)
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
    return depths


def _close(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text)


def parse_class(raw, package, path):
    """Return the top-level Type of one .cls file, with its inner types, or None."""
    text = strip(raw)
    depths = _depths(text)
    spans = []  # (body_start, body_end, body_depth, Type)
    top = None
    for m in TYPE_DECL.finditer(text):
        brace = text.find("{", m.end())
        if brace < 0:
            continue
        line = text.count("\n", 0, m.start(4)) + 1
        outer = None
        for start, end, depth, t in spans:
            if start < m.start(4) < end and depths[m.start(4)] == depth:
                outer = t
        if top is not None and outer is None:
            continue
        t = Type(m.group(4), outer, package, path, _annots(m.group(1)), _words(m.group(2)), m.group(3).lower(), line)
        if outer is None:
            top = t
        else:
            outer.members.setdefault(t.name.lower(), []).append(t)
        spans.append((brace, _close(text, brace), depths[brace] + 1, t))
    if top is None:
        return None
    for m in MEMBER_DECL.finditer(text):
        type_ref, name = m.group(3), m.group(4)
        if type_ref and type_ref.lower() in NOT_TYPES or name.lower() in NOT_TYPES:
            continue
        owner = None
        for start, end, depth, t in spans:
            if start < m.start(4) < end and depths[m.start(4)] == depth:
                owner = t
        if owner is None:
            continue
        annots, mods = _annots(m.group(1)), _words(m.group(2))
        line = text.count("\n", 0, m.start(4)) + 1
        if not type_ref and m.group(5) == "(" and name.lower() == owner.name.lower():
            close = text.find(")", m.end())
            no_arg = close >= 0 and not text[m.end() : close].strip()
            owner.ctors.append(Member(name, "ctor", annots, mods, line, no_arg))
        elif type_ref:
            kind = "method" if m.group(5) == "(" else "field"
            owner.members.setdefault(name.lower(), []).append(
                Member(name, kind, annots, mods, line, type_ref=type_ref.strip())
            )
    return top


def packages(root):
    """{package dir name: set of the dir names it depends on, directly or not}."""
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as f:
        project = json.load(f)
    by_name = {d["package"]: os.path.basename(d["path"]) for d in project["packageDirectories"]}
    direct = {
        os.path.basename(d["path"]): {by_name[x["package"]] for x in d.get("dependencies", [])}
        for d in project["packageDirectories"]
    }
    deps = {}
    for pkg in direct:
        seen, todo = set(), list(direct[pkg])
        while todo:
            p = todo.pop()
            if p not in seen:
                seen.add(p)
                todo.extend(direct.get(p, ()))
        deps[pkg] = seen
    return deps


class Index:
    """Every packaged class: top-level types by name, raw and stripped source by name."""

    def __init__(self, sources, deps):
        """sources: {path: raw text} with paths like packages/<pkg>/main/.../X.cls."""
        self.deps = deps
        self.types = {}
        self.raw = {}
        self.text = {}
        for path in sorted(sources):
            package = path.replace("\\", "/").split("/")[1]
            top = parse_class(sources[path], package, path)
            if top is None:
                continue
            self.types[top.name] = top
            self.raw[top.name] = sources[path]
            self.text[top.name] = strip(sources[path])

    def find(self, qualified):
        """Look up 'Outer' or 'Outer.Inner' (Apex names are case insensitive)."""
        parts = qualified.split(".")
        top = self.types.get(parts[0]) or next(
            (t for n, t in self.types.items() if n.lower() == parts[0].lower()), None
        )
        if top is None or len(parts) > 2:
            return None
        if len(parts) == 1:
            return top
        inner = [m for m in top.members.get(parts[1].lower(), []) if isinstance(m, Type)]
        return inner[0] if inner else None


def load(root="."):
    files = glob.glob(os.path.join(root, "packages/*/main/**/*.cls"), recursive=True)
    sources = {}
    for f in files:
        with open(f, encoding="utf-8") as fh:
            sources[os.path.relpath(f, root)] = fh.read()
    return Index(sources, packages(root))


def registry_handlers(root="."):
    """[(path, class name)] for every Automation_Registry__mdt record's Handler_Class__c."""
    out = []
    pattern = os.path.join(root, "packages/*/main/default/customMetadata/Automation_Registry.*.md-meta.xml")
    ns = {"m": "http://soap.sforce.com/2006/04/metadata"}
    for f in sorted(glob.glob(pattern)):
        for values in ElementTree.parse(f).getroot().findall("m:values", ns):
            if values.findtext("m:field", namespaces=ns) == "Handler_Class__c":
                value = (values.findtext("m:value", namespaces=ns) or "").strip()
                if value:
                    out.append((os.path.relpath(f, root), value))
    return out


def read_allowlist(path):
    """{(referencing class, target)} from 'Class Target: reason' lines; a missing reason is an error."""
    entries, errors = {}, []
    if not os.path.exists(path):
        return entries, errors
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^(\w+)\s+([\w.]+)\s*:\s*(\S.*)$", line)
            if not m:
                errors.append(f"{path}:{n}: expected 'ReferencingClass Target: reason'")
                continue
            entries[(m.group(1), m.group(2))] = n
    return entries, errors


if __name__ == "__main__":
    sys.exit(0)
