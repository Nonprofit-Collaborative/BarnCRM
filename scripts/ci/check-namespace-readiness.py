#!/usr/bin/env python3
"""Fails on Lightning and label references that work unmanaged but not once packages split.

Every package shares one namespace (ADR-0017), but each is its own 2GP package, and unmanaged
deploys put everything in one bucket, so neither deploys nor org tests show these:

1. Components. A `c/x` import or `<c-x>` tag in one package's LWC, or a flexipage
   `componentName` naming `x`, where `x` is another package's component: that package must be
   a dependency, `x` must be `isExposed` true, and for a flexipage `x` must list the page's
   target (`lightning__AppPage` for an AppPage). Jest tests are not packaged and are skipped.
2. Labels. Another package's custom label used in Apex (`Label.X`), LWC
   (`@salesforce/label/c.X`) or metadata (`$Label.X`) must be `<protected>false</protected>`.
3. Page state keys. LWC JavaScript never writes a literal `c__` state key: inside a managed
   package the prefix is the namespace, so the key comes from Apex (`NamespaceUtil.stateKey`)
   or is matched by its `__name` suffix (`settingsConsole`, `findRecords`).
4. Packaged API names. LWC never writes a packaged object, field or tab name as a literal:
   once the namespace is set the name carries the prefix. Flagged: a `__c`, `__r`, `__mdt`,
   `__e`, `__x` or `__b` name (with no namespace of its own) as a NavigationMixin
   `objectApiName`, in an `objectApiName` comparison, in a dotted record field path
   (`getRecord` fields, `getFieldValue`), or in an HTML `field-name` or `object-api-name`
   attribute; and a packaged tab name (any `tabs/*.tab-meta.xml`) as an `apiName`, written
   directly or through a `const`. Objects and fields come from `@salesforce/schema` imports,
   tab names from Apex (`TabNamesController.tabApiNames`).

4. sfdx-project.json is ready for `sf package version create` (docs/contributor-guide/ci.md,
   "Creating package versions"): every package whose source has an InstallHandler class names
   it as `postInstallScript`, and every dependency on another BarnCRM package carries a
   `versionNumber` of `<that package's major.minor.patch>.LATEST`.

A known exception goes in DEFERRED below with its reason; an entry that matches nothing fails.
"""

import glob
import importlib.util
import json
import os
import re
import sys
from xml.etree import ElementTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apex_visibility as av  # noqa: E402
from apex_source import strip  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "upgrade_helper", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "org", "package-upgrade-helper.py")
)
helper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(helper)

NS = {"m": "http://soap.sforce.com/2006/04/metadata"}
PAGE_TARGETS = {
    "AppPage": "lightning__AppPage",
    "RecordPage": "lightning__RecordPage",
    "HomePage": "lightning__HomePage",
    "UtilityBar": "lightning__UtilityBar",
}

# path: reason. Components allowed to write a literal `c__` key. None today.
DEFERRED = {}

# A packaged object or field name: one `__` and a packaged suffix (`npsp__X__c` is someone else's).
PACKAGED = re.compile(r"^[A-Za-z][A-Za-z0-9_]*?__(?:c|r|mdt|e|x|b)$")


def packaged(name):
    return bool(PACKAGED.match(name)) and name.count("__") == 1


def tab_names(sources):
    return {m.group(1) for p in sources for m in [re.search(r"/tabs/(\w+)\.tab-meta\.xml$", p)] if m}


def api_name_problems(path, text, tabs):
    """[(pos, message)] for rule 4 in one LWC .js (comments blanked) or .html file."""
    out = []
    if path.endswith(".html"):
        for m in re.finditer(r"\b(field-name|object-api-name)\s*=\s*\"([\w.]+)\"", text):
            if any(packaged(part) for part in m.group(2).split(".")):
                out.append((m.start(), f"literal packaged name {m.group(2)} in {m.group(1)}"))
        return out
    consts = dict(re.findall(r"\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*['\"`](\w+)['\"`]\s*;", text))
    for m in re.finditer(r"\bobjectApiName\s*:\s*['\"`](\w+)['\"`]", text):
        if packaged(m.group(1)):
            out.append((m.start(), f"literal packaged object {m.group(1)} as objectApiName"))
    compare = r"objectApiName\s*[!=]==?\s*['\"`](\w+)['\"`]|['\"`](\w+)['\"`]\s*[!=]==?\s*[\w$.?]*objectApiName\b"
    for m in re.finditer(compare, text):
        name = m.group(1) or m.group(2)
        if packaged(name):
            out.append((m.start(), f"literal packaged object {name} in an objectApiName comparison"))
    # `const TABS = { find: 'Find' }` read as `apiName: TABS.find` or `apiName: TABS[key]`.
    maps = {}
    for m in re.finditer(r"\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*\{([^{}]*)\}", text):
        maps[m.group(1)] = re.findall(r"['\"`](\w+)['\"`]", m.group(2))
    for m in re.finditer(r"(?<![\w$.])apiName\s*:\s*(?:['\"`](\w+)['\"`]|([A-Za-z_$][\w$]*)\b)", text):
        names = [m.group(1) or consts.get(m.group(2))] + maps.get(m.group(2), [])
        for name in sorted({n for n in names if n in tabs}):
            out.append((m.start(), f"literal packaged tab {name} as apiName"))
    for m in re.finditer(r"['\"`](\w+(?:\.\w+)+)['\"`]", text):
        parts = m.group(1).split(".")
        # A path on another package's object (`npsp__X__c.Y__c`) is not ours.
        if any(packaged(part) for part in parts) and parts[0].count("__") < 2:
            out.append((m.start(), f"literal packaged field path {m.group(1)}"))
    return out


def package_of(path):
    return path.replace("\\", "/").split("/")[1]


def strip_js(source):
    """Blank out JavaScript comments, keeping strings, offsets and line numbers."""
    out, i, n, quote = [], 0, len(source), None
    while i < n:
        c = source[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(source[i + 1])
                i += 1
            elif c == quote:
                quote = None
            i += 1
        elif c in "'\"`":
            quote = c
            out.append(c)
            i += 1
        elif source.startswith("//", i) or source.startswith("/*", i):
            end = source.find("\n", i) if source[i + 1] == "/" else source.find("*/", i + 2) + 2
            end = n if end < 2 else end
            out.append(re.sub(r"[^\n]", " ", source[i:end]))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def camel(tag):
    return re.sub(r"-([a-z0-9])", lambda m: m.group(1).upper(), tag)


def components(sources):
    """{name: (package, exposed, targets)} from the .js-meta.xml files in sources."""
    out = {}
    for path, text in sources.items():
        if not path.endswith(".js-meta.xml"):
            continue
        root = ElementTree.fromstring(text)
        exposed = (root.findtext("m:isExposed", namespaces=NS) or "").strip() == "true"
        targets = {t.text.strip() for t in root.findall("m:targets/m:target", NS) if t.text}
        out[os.path.basename(path)[: -len(".js-meta.xml")]] = (package_of(path), exposed, targets)
    return out


def labels(sources):
    """{name: (package, protected)}; a label with no <protected> element is protected."""
    out = {}
    for path, text in sources.items():
        if path.endswith(".labels-meta.xml"):
            for block in re.findall(r"<labels>(.*?)</labels>", text, re.DOTALL):
                name = re.search(r"<fullName>\s*(\w+)\s*</fullName>", block)
                prot = re.search(r"<protected>\s*(\w+)\s*</protected>", block)
                if name:
                    out[name.group(1)] = (package_of(path), not prot or prot.group(1) != "false")
    return out


def check(sources, deps):
    """[(path, line, message)] for every problem in sources ({path: text})."""
    comps, labs, tabs, problems = components(sources), labels(sources), tab_names(sources), []

    def line(text, pos):
        return text.count("\n", 0, pos) + 1

    def other_package(path, owner):
        pkg = package_of(path)
        if owner == pkg:
            return None
        if owner not in deps.get(pkg, set()):
            return f"is in {owner}, which {pkg} does not depend on"
        return ""

    for path, text in sorted(sources.items()):
        lwc = "/lwc/" in path and "/__tests__/" not in path
        refs = []  # (pos, component name, flexipage target or None)
        if lwc and path.endswith(".js"):
            code = strip_js(text)
            refs += [(m.start(), m.group(1), None) for m in re.finditer(r"['\"]c/(\w+)['\"]", code)]
            for m in re.finditer(r"['\"`]c__\w+|(?<![\w.])c__\w+\s*:", code):
                if path not in DEFERRED:
                    problems.append((path, line(code, m.start()), "literal c__ page state key"))
            problems += [(path, line(code, pos), msg) for pos, msg in api_name_problems(path, code, tabs)]
        if lwc and path.endswith(".html"):
            problems += [(path, line(text, pos), msg) for pos, msg in api_name_problems(path, text, tabs)]
            refs += [(m.start(), camel(m.group(1)), None) for m in re.finditer(r"<c-([a-z0-9-]+)", text)]
        if path.endswith(".flexipage-meta.xml"):
            page = ElementTree.fromstring(text).findtext("m:type", namespaces=NS)
            for m in re.finditer(r"<componentName>\s*(?:c:)?(\w+)\s*</componentName>", text):
                refs.append((m.start(), m.group(1), PAGE_TARGETS.get(page)))
        for pos, name, target in refs:
            if name not in comps:
                continue
            owner, exposed, targets = comps[name]
            why = other_package(path, owner)
            if why is None:
                continue
            if why:
                problems.append((path, line(text, pos), f"component {name} {why}"))
            elif not exposed:
                problems.append((path, line(text, pos), f"component {name} is {owner}'s and not isExposed"))
            elif target and target not in targets:
                problems.append((path, line(text, pos), f"component {name} has no {target} target"))

        if path.endswith((".cls", ".trigger")):
            used = re.finditer(r"(?<![\w.])(?:System\s*\.\s*)?Label\s*\.\s*(\w+)", strip(text))
        elif lwc and path.endswith(".js"):
            used = re.finditer(r"@salesforce/label/c\.(\w+)", text)
        elif path.endswith(".xml") and not path.endswith(".labels-meta.xml"):
            used = re.finditer(r"\$Label\.(\w+)", text)
        else:
            used = ()
        for m in used:
            if m.group(1) not in labs:
                continue
            owner, protected = labs[m.group(1)]
            why = other_package(path, owner)
            if why is None:
                continue
            if why:
                problems.append((path, line(text, m.start()), f"label {m.group(1)} {why}"))
            elif protected:
                problems.append((path, line(text, m.start()), f"label {m.group(1)} is {owner}'s and protected"))

    for path in DEFERRED:
        if path in sources and not re.search(r"['\"`]c__\w+|(?<![\w.])c__\w+\s*:", strip_js(sources[path])):
            problems.append((path, 1, "DEFERRED entry matches nothing; remove it"))
    return problems


def check_project(project, handler_of):
    """[(path, line, message)] for what `sf package version create` needs in sfdx-project.json.

    handler_of(path) is the InstallHandler class in that package directory, or None."""
    problems, where = [], "sfdx-project.json"
    dirs = helper.directories(project)
    versions = {d.get("package"): d.get("versionNumber", "") for _, d in dirs}
    for key, d in dirs:
        handler = handler_of(d["path"])
        if handler and d.get("postInstallScript") != handler:
            problems.append((where, 1, f"{key}: postInstallScript must be {handler}, its InstallHandler"))
        elif not handler and d.get("postInstallScript"):
            problems.append((where, 1, f"{key}: postInstallScript {d['postInstallScript']} is not an InstallHandler here"))
        for dep in d.get("dependencies", []):
            if dep.get("package") not in versions:
                continue
            want = ".".join(versions[dep["package"]].split(".")[:3]) + ".LATEST"
            if dep.get("versionNumber") != want:
                problems.append((where, 1, f"{key}: dependency {dep['package']} needs versionNumber {want}"))
    return problems


def main():
    paths = [
        p
        for p in glob.glob("packages/*/main/**/*", recursive=True)
        if os.path.isfile(p) and p.endswith((".cls", ".trigger", ".js", ".html", ".xml"))
    ]
    sources = {}
    for p in paths:
        with open(p, encoding="utf-8") as f:
            sources[p.replace(os.sep, "/")] = f.read()
    problems = check(sources, av.packages("."))
    with open("sfdx-project.json", encoding="utf-8") as f:
        problems += check_project(json.load(f), lambda path: helper.install_handler(".", path))
    for path, n, message in problems:
        print(f"{path}:{n}: {message}")
    if problems:
        print(f"{len(problems)} problem(s). See the docstring of {os.path.basename(__file__)}.")
        return 1
    print(f"Components, labels, page state keys and API names in {len(sources)} files, and sfdx-project.json, are namespace ready.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
