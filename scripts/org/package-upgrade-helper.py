#!/usr/bin/env python3
"""Helper for scripts/org/package-upgrade-test.sh: everything that reads JSON or source.

The shell script runs the steps; this file answers its questions, offline, from
sfdx-project.json, the package source and the sf CLI's JSON output. It never contacts an org
and never prints anything from an sf result except the fields it was asked for, so an access
token in `sf org create scratch --json` output is never echoed or written.

Subcommands (all print to stdout, tab separated, one item per line):
  namespace   --project P                       the namespace (may be empty)
  packages    --project P --root R --select S   key, package name, path, install handler
                                                class (or -), in dependency order; S is
                                                "all" or a comma list, dependencies added
  dependents  --project P --key K --select S    selected packages that need K (any depth)
  shape       --root R NAME                     definition file, edition, org name
  versions    --file F --select S               key and 04t id per selected package
  aliases     --project P --select S            key, package name, 0Ho id or - (create-versions.sh)
  limit       NAME                              remaining and max of a limit, from sf limits JSON
  readiness   (see parse_readiness)             OK / MISSING / NOTE lines; exit 1 on MISSING
  render      TEMPLATE OUT --ns NS [--set K=V] [--module KEY --root R]
  jget        PATH                              a value from the JSON on stdin
  installed   --expect NAME=04t ... --absent NAME ...   checks `sf package installed list --json`
  objects     --select S --ns NS                the record counts compared across the upgrade
  summary     --steps TSV --out DIR --meta K=V ...      writes summary.json and summary.md
"""

import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

SHAPES = {
    "platform": "platform-only.json",
    "sales": "sales-cloud.json",
    "npsp": "npsp.json",
    "npc": "nonprofit-cloud.json",
}

# Objects whose record counts must not change across the upgrade: what the C-10 sample data
# writes, per package. A package with no sample data has no entry.
COUNTED = {
    "core": ["Account", "Contact", "Household_Member__c", "Relationship__c", "Affiliation__c"],
    "giving": ["Gift__c", "Gift_Allocation__c", "Fund__c"],
    "volunteers": ["Volunteer_Hours__c", "Volunteer_Job__c"],
}

# Classes the shell script calls from anonymous Apex outside the templates:
# seed-sample-data.sh --namespace runs <ns>.SampleDataLoader.load().
EXTRA_ENTRY_POINTS = ["core:SampleDataLoader"]

ID_04T = re.compile(r"^04t[0-9A-Za-z]{12}([0-9A-Za-z]{3})?$")
NS_REF = re.compile(r"%%NS%%\.([A-Za-z_][A-Za-z0-9_]*)")


def fail(message, code=2):
    print(message, file=sys.stderr)
    sys.exit(code)


def read_project(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        fail(f"cannot read {path}: {error}")


def directories(project):
    """Package directories as (key, entry), keyed by folder name, in file order."""
    return [(os.path.basename(d["path"].rstrip("/")), d) for d in project.get("packageDirectories", [])]


def dependency_map(project):
    dirs = directories(project)
    by_name = {d.get("package"): key for key, d in dirs}
    deps = {}
    for key, d in dirs:
        deps[key] = [by_name[x["package"]] for x in d.get("dependencies", []) if x.get("package") in by_name]
    return dirs, deps


def ordered(project):
    """Keys in dependency order: file order, each package after everything it needs."""
    dirs, deps = dependency_map(project)
    done, out = set(), []
    keys = [key for key, _ in dirs]
    while len(out) < len(keys):
        progressed = False
        for key in keys:
            if key not in done and all(dep in done for dep in deps[key]):
                done.add(key)
                out.append(key)
                progressed = True
        if not progressed:
            fail("sfdx-project.json dependencies form a cycle: " + ", ".join(k for k in keys if k not in done))
    return out


def select(project, wanted):
    order = ordered(project)
    if wanted in ("", "all"):
        return order, []
    _, deps = dependency_map(project)
    asked = [w.strip() for w in wanted.split(",") if w.strip()]
    unknown = [w for w in asked if w not in order]
    if unknown:
        fail("unknown package(s): " + ", ".join(unknown) + ". Known: " + ", ".join(order))
    chosen = set()

    def add(key):
        if key not in chosen:
            chosen.add(key)
            for dep in deps[key]:
                add(dep)

    for key in asked:
        add(key)
    added = [k for k in order if k in chosen and k not in asked]
    return [k for k in order if k in chosen], added


def install_handler(root, path):
    """The class in a package that implements InstallHandler, or None."""
    for cls in sorted(glob.glob(os.path.join(root, path, "main", "default", "classes", "*.cls"))):
        with open(cls, encoding="utf-8") as handle:
            text = handle.read()
        if re.search(r"\bclass\s+\w+\s+implements\s+[^{]*\bInstallHandler\b", text):
            return os.path.basename(cls)[:-4]
    return None


def class_file(root, project, name):
    for _, d in directories(project):
        path = os.path.join(root, d["path"], "main", "default", "classes", name + ".cls")
        if os.path.exists(path):
            return path
    return None


def is_global(root, project, name):
    path = class_file(root, project, name)
    if not path:
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return re.search(r"^\s*global\b[^{;]*\bclass\s+" + re.escape(name) + r"\b", text, re.M) is not None


def cmd_namespace(args):
    print(read_project(args.project).get("namespace", ""))


def cmd_packages(args):
    project = read_project(args.project)
    keys, added = select(project, args.select)
    entries = dict(directories(project))
    if added:
        print("added because a chosen package needs them: " + ", ".join(added), file=sys.stderr)
    for key in keys:
        d = entries[key]
        print("\t".join([key, d.get("package", key), d["path"], install_handler(args.root, d["path"]) or "-"]))


def cmd_dependents(args):
    project = read_project(args.project)
    keys, _ = select(project, args.select)
    _, deps = dependency_map(project)

    def needs(key, target):
        return any(dep == target or needs(dep, target) for dep in deps[key])

    for key in keys:
        if key != args.key and needs(key, args.key):
            print(key)


def cmd_shape(args):
    if args.name not in SHAPES:
        fail(f"unknown shape: {args.name}. Known: " + ", ".join(SHAPES))
    rel = os.path.join("config", "scratch-defs", SHAPES[args.name])
    path = os.path.join(args.root, rel)
    if not os.path.exists(path):
        fail(f"shape {args.name}: {rel} does not exist")
    definition = read_project(path)
    print("\t".join([rel, definition.get("edition", "-"), definition.get("orgName", "-")]))


def read_versions(path, keys):
    found = {}
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 2 or not ID_04T.match(parts[1]):
                fail(f"{path}:{number}: expected '<package key> <04t id>', got: {line}")
            found[parts[0]] = parts[1]
    missing = [k for k in keys if k not in found]
    if missing:
        fail(f"{path} has no 04t id for: " + ", ".join(missing))
    return found


def cmd_aliases(args):
    """Key, package name and its 0Ho id (or -) per selected package, for create-versions.sh."""
    project = read_project(args.project)
    keys, _ = select(project, args.select)
    entries, aliases = dict(directories(project)), project.get("packageAliases", {})
    for key in keys:
        name = entries[key].get("package", key)
        alias = str(aliases.get(name, ""))
        print("\t".join([key, name, alias if alias.startswith("0Ho") else "-"]))


def cmd_limit(args):
    """'<remaining> <max>' of one Dev Hub limit from `sf limits api display --json` on stdin."""
    try:
        rows = json.load(sys.stdin).get("result", [])
    except (ValueError, AttributeError):
        return
    for row in rows if isinstance(rows, list) else []:
        if row.get("name") == args.name:
            print(f"{row.get('remaining')} {row.get('max')}")


def cmd_versions(args):
    project = read_project(args.project)
    keys, _ = select(project, args.select)
    found = read_versions(args.file, keys)
    for key in keys:
        print(f"{key}\t{found[key]}")


def project_at(root, ref):
    try:
        text = subprocess.run(
            ["git", "-C", root, "show", f"{ref}:sfdx-project.json"], capture_output=True, text=True, check=True
        ).stdout
        return json.loads(text)
    except (subprocess.CalledProcessError, ValueError):
        return None


def version_tuple(value):
    parts = (value or "").split(".")
    try:
        return tuple(int(p) for p in parts[:3])
    except ValueError:
        return None


def templates_for(templates_dir, keys, uninstall):
    names = ["health-check.apex"]
    names += [f"smoke-{k}.apex" for k in keys if os.path.exists(os.path.join(templates_dir, f"smoke-{k}.apex"))]
    if uninstall:
        names.append("uninstall-check.apex")
    return [os.path.join(templates_dir, n) for n in names]


def check_build_source(add, label, ref, at, keys, namespace, managed, needs_ancestor, root, current):
    """What `sf package version create` needs in the sfdx-project.json at a ref it builds."""
    where = f"{label} {ref}"
    if at is None:
        add("MISSING", f"{where}: no readable sfdx-project.json at that ref")
        return
    ns_at = at.get("namespace", "")
    ok = bool(namespace) and ns_at == namespace
    add("OK" if ok else "MISSING", f"{where}: namespace '{ns_at}'" + ("" if ok else
        f", must be '{namespace or '<the registered namespace>'}' (build only from commits after it is set)"))
    entries = dict(directories(at))
    absent = [k for k in keys if k not in entries]
    if absent:
        add("MISSING", f"{where}: packages not in its sfdx-project.json: " + ", ".join(absent))
    keys = [k for k in keys if k in entries]

    def which(found):
        return f"all {len(keys)} chosen packages" if len(found) == len(keys) > 1 else ", ".join(found)

    aliases = at.get("packageAliases", {})
    lacking = [k for k in keys if not str(aliases.get(entries[k]["package"], "")).startswith("0Ho")]
    add("MISSING" if lacking else "OK", f"{where}: packageAliases has no 0Ho package id for " + which(lacking)
        if lacking else f"{where}: packageAliases has a 0Ho id for every chosen package")
    loose = [k for k in keys if any(not x.get("versionNumber") for x in entries[k].get("dependencies", []))]
    add("MISSING" if loose else "OK", f"{where}: dependencies need a versionNumber (e.g. \"0.1.0.LATEST\") on " +
        which(loose) if loose else f"{where}: every dependency has a versionNumber")
    if not managed:
        return
    # The InstallHandler classes are read from the current source; a ref that predates one is
    # caught by the version create itself.
    with_handler = [k for k in keys if install_handler(root, current[k]["path"])]
    unset = [k for k in with_handler if entries[k].get("postInstallScript") != install_handler(root, current[k]["path"])]
    add("MISSING" if unset else "OK", f"{where}: postInstallScript (the package's <Module>PostInstall class) not set "
        "on " + which(unset) if unset else f"{where}: postInstallScript set for every package with an InstallHandler")
    if needs_ancestor:
        bare = [k for k in keys if not (entries[k].get("ancestorVersion") or entries[k].get("ancestorId"))]
        add("MISSING" if bare else "OK", f"{where}: a managed upgrade needs ancestorVersion (e.g. \"HIGHEST\") or "
            "ancestorId on " + which(bare) if bare else f"{where}: every package names its ancestor")


def cmd_readiness(args):
    project = read_project(args.project)
    keys, _ = select(project, args.select)
    entries = dict(directories(project))
    namespace = project.get("namespace", "")
    lines = []

    def add(status, text):
        lines.append((status, text))

    managed = args.type == "managed"

    add("OK" if namespace else "MISSING", f"namespace: {namespace}" if namespace else
        "namespace: empty in sfdx-project.json (D-87: register it and set it first)")
    add("OK" if args.devhub else "MISSING", f"Dev Hub: {args.devhub}" if args.devhub else
        "Dev Hub: --devhub not given (the CLI default is never used)")

    for label, kind, ref in (("--from", args.from_kind, args.from_ref), ("--to", args.to_kind, args.to_ref)):
        if kind == "ref":
            check_build_source(add, label, ref, project_at(args.root, ref), keys, namespace, managed,
                               label == "--to", args.root, entries)
    if args.from_kind == "ref" and args.to_kind == "ref" and args.from_ref == args.to_ref:
        add("NOTE", "--from and --to are the same ref: the upgrade carries no changes")

    if managed:
        if args.from_kind == "ref":
            if args.promote:
                add("NOTE", "N-1 is built from a git ref and PROMOTED (--promote-from): permanent, owner approval required")
                at_from, at_to = project_at(args.root, args.from_ref), project_at(args.root, args.to_ref) if args.to_kind == "ref" else None
                if at_from and at_to:
                    old = {os.path.basename(d["path"]): d.get("versionNumber") for d in at_from.get("packageDirectories", [])}
                    new = {os.path.basename(d["path"]): d.get("versionNumber") for d in at_to.get("packageDirectories", [])}
                    stale = [k for k in keys if version_tuple(new.get(k)) is None or version_tuple(old.get(k)) is None
                             or version_tuple(new.get(k)) <= version_tuple(old.get(k))]
                    add("MISSING" if stale else "OK", "a promoted N-1 needs a higher major.minor.patch at --to for: " +
                        ", ".join(stale) if stale else "versionNumber at --to is above --from for every package")
            else:
                add("MISSING", "managed N-1 from a git ref would be a beta, and a beta cannot be upgraded: pass "
                    "--promote-from (permanent, owner approval) or --from <file of released 04t ids>")
        else:
            add("NOTE", "managed N-1 from a 04t list: every id must be a released (promoted) version")
    else:
        add("NOTE", "unlocked: post-install scripts run for managed packages only, so this run calls each "
            "package's runSetup as the admin after every install and upgrade")

    entry_points = []
    for template in templates_for(args.templates, keys, args.uninstall):
        with open(template, encoding="utf-8") as handle:
            entry_points += [(os.path.basename(template), name) for name in NS_REF.findall(handle.read())]
    entry_points += [("seed-sample-data.sh", e.split(":", 1)[1]) for e in EXTRA_ENTRY_POINTS if e.split(":", 1)[0] in keys]
    if not managed:
        entry_points += [("post-install.apex", h) for h in (install_handler(args.root, entries[k]["path"]) for k in keys) if h]
    not_global = sorted({name for _, name in entry_points if is_global(args.root, project, name) is False})
    unknown = sorted({name for _, name in entry_points if is_global(args.root, project, name) is None})
    add("MISSING" if not_global else "OK", "not global, so anonymous Apex in a subscriber org cannot call them: " +
        ", ".join(not_global) if not_global else "every Apex entry point the checks call is global")
    if unknown:
        add("MISSING", "entry points with no class in the source: " + ", ".join(unknown))

    shapes = [s for s in args.shapes.split(",") if s]
    if "npsp" in shapes:
        with open(os.path.join(args.root, "scripts", "org", "install-npsp.sh"), encoding="utf-8") as handle:
            empty = re.search(r"^NPSP_PACKAGE_IDS=\(\)", handle.read(), re.M)
        add("MISSING" if empty else "OK", "npsp shape: scripts/org/install-npsp.sh has no verified NPSP ids yet" if empty else
            "npsp shape: install-npsp.sh has NPSP ids")
    if "npc" in shapes:
        add("NOTE", "npc shape: needs a Dev Hub entitled to Nonprofit Cloud; its definition is unverified (scratch-orgs.md)")
    add("NOTE", f"creates {len(shapes)} scratch org(s), one per shape: owner approval, and the Dev Hub's daily and active limits")
    if args.uninstall:
        add("NOTE", f"--uninstall-check removes {args.uninstall} after the upgrade and checks Core and what it left")

    for status, text in lines:
        print(f"{status:<8} {text}")
    sys.exit(1 if any(s == "MISSING" for s, _ in lines) else 0)


def apex_list(values):
    return ", ".join("'" + v.replace("'", "\\'") + "'" for v in values) or "''"


def cmd_render(args):
    with open(args.template, encoding="utf-8") as handle:
        text = handle.read()
    values = {"NS": args.ns}
    for pair in args.set or []:
        key, _, value = pair.partition("=")
        values[key] = value
    if args.module:
        project = read_project(args.project)
        path = dict(directories(project))[args.module]["path"]
        base = os.path.join(args.root, path, "main", "default")
        classes = sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(base, "classes", "*.cls")))
        objects = sorted(
            os.path.basename(p) for p in glob.glob(os.path.join(base, "objects", "*"))
            if re.search(r"__(c|mdt|e)$", os.path.basename(p))
        )
        values["MODULE"] = args.module
        values["MODULE_CLASSES"] = apex_list(classes)
        values["MODULE_OBJECTS"] = apex_list(f"{args.ns}__{o}" for o in objects)
    for key, value in values.items():
        text = text.replace(f"%%{key}%%", value)
    left = re.findall(r"%%[A-Z_]+%%", text)
    if left:
        fail(f"{args.template}: no value for " + ", ".join(sorted(set(left))))
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(text)


def cmd_jget(args):
    try:
        value = json.load(sys.stdin)
    except ValueError:
        return
    for part in args.path.split("."):
        if isinstance(value, list) and part.isdigit() and int(part) < len(value):
            value = value[int(part)]
        elif isinstance(value, dict) and part in value:
            value = value[part]
        else:
            return
    print(json.dumps(value) if isinstance(value, (dict, list)) else value)


def cmd_installed(args):
    try:
        rows = json.load(sys.stdin).get("result") or []
    except ValueError:
        fail("sf package installed list did not return JSON", 1)
    have = {r.get("SubscriberPackageName"): r.get("SubscriberPackageVersionId") for r in rows}
    problems = []
    for pair in args.expect or []:
        name, _, wanted = pair.rpartition("=")
        if have.get(name) != wanted:
            problems.append(f"{name}: expected {wanted}, found {have.get(name) or 'not installed'}")
    for name in args.absent or []:
        if name in have:
            problems.append(f"{name}: still installed ({have[name]})")
    for line in problems:
        print(line)
    sys.exit(1 if problems else 0)


def cmd_objects(args):
    project = read_project(args.project)
    keys, _ = select(project, args.select)
    for key in keys:
        for name in COUNTED.get(key, []):
            print(f"{args.ns}__{name}" if name.endswith("__c") else name)


def cmd_summary(args):
    meta = dict(pair.partition("=")[::2] for pair in args.meta or [])
    shapes = {}
    with open(args.steps, encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            shape, step, status, seconds = parts[:4]
            message = parts[4] if len(parts) > 4 else ""
            shapes.setdefault(shape, []).append(
                {"step": step, "status": status, "seconds": int(seconds or 0), "message": message}
            )
    result = {
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **meta,
        "passed": all(s["status"] != "fail" for steps in shapes.values() for s in steps),
        "shapes": [
            {"shape": name, "passed": all(s["status"] != "fail" for s in steps),
             "seconds": sum(s["seconds"] for s in steps), "steps": steps}
            for name, steps in shapes.items()
        ],
    }
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "summary.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")
    md = ["# Package Install and Upgrade Test", ""]
    md += [f"- **{k}:** {v}" for k, v in meta.items()]
    md += [f"- **Result:** {'PASS' if result['passed'] else 'FAIL'}", ""]
    for shape in result["shapes"]:
        md += [f"## {shape['shape']}: {'PASS' if shape['passed'] else 'FAIL'} ({shape['seconds']} s)", "",
               "| Step | Result | Seconds | Detail |", "|---|---|---|---|"]
        md += [f"| {s['step']} | {s['status'].upper()} | {s['seconds']} | {s['message'].replace('|', '/')} |"
               for s in shape["steps"]]
        md.append("")
    with open(os.path.join(args.out, "summary.md"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(md))
    print("PASS" if result["passed"] else "FAIL")


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    def with_project(p):
        p.add_argument("--project", default=os.path.join(root, "sfdx-project.json"))
        p.add_argument("--root", default=root)
        return p

    with_project(sub.add_parser("namespace")).set_defaults(run=cmd_namespace)
    p = with_project(sub.add_parser("packages"))
    p.add_argument("--select", default="all")
    p.set_defaults(run=cmd_packages)
    p = with_project(sub.add_parser("dependents"))
    p.add_argument("--select", default="all")
    p.add_argument("--key", required=True)
    p.set_defaults(run=cmd_dependents)
    p = with_project(sub.add_parser("shape"))
    p.add_argument("name")
    p.set_defaults(run=cmd_shape)
    p = with_project(sub.add_parser("aliases"))
    p.add_argument("--select", default="all")
    p.set_defaults(run=cmd_aliases)
    p = sub.add_parser("limit")
    p.add_argument("name")
    p.set_defaults(run=cmd_limit)
    p = with_project(sub.add_parser("versions"))
    p.add_argument("--select", default="all")
    p.add_argument("--file", required=True)
    p.set_defaults(run=cmd_versions)
    p = with_project(sub.add_parser("readiness"))
    p.add_argument("--select", default="all")
    p.add_argument("--type", choices=["managed", "unlocked"], required=True)
    p.add_argument("--devhub", default="")
    p.add_argument("--from-kind", choices=["ref", "list"], required=True)
    p.add_argument("--from-ref", default="")
    p.add_argument("--to-kind", choices=["ref", "list"], required=True)
    p.add_argument("--to-ref", default="")
    p.add_argument("--promote", action="store_true")
    p.add_argument("--shapes", default="")
    p.add_argument("--uninstall", default="")
    p.add_argument("--templates", default=os.path.join(here, "package-upgrade-test"))
    p.set_defaults(run=cmd_readiness)
    p = with_project(sub.add_parser("render"))
    p.add_argument("template")
    p.add_argument("out")
    p.add_argument("--ns", required=True)
    p.add_argument("--set", action="append")
    p.add_argument("--module")
    p.set_defaults(run=cmd_render)
    p = sub.add_parser("jget")
    p.add_argument("path")
    p.set_defaults(run=cmd_jget)
    p = sub.add_parser("installed")
    p.add_argument("--expect", action="append")
    p.add_argument("--absent", action="append")
    p.set_defaults(run=cmd_installed)
    p = with_project(sub.add_parser("objects"))
    p.add_argument("--select", default="all")
    p.add_argument("--ns", required=True)
    p.set_defaults(run=cmd_objects)
    p = sub.add_parser("summary")
    p.add_argument("--steps", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--meta", action="append")
    p.set_defaults(run=cmd_summary)
    args = parser.parse_args(argv)
    args.run(args)


if __name__ == "__main__":
    main(sys.argv[1:])
