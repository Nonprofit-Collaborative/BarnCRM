#!/usr/bin/env python3
"""Writes the destructive manifest for a release: every component one ref has and the next lacks.

    build-destructive-manifest.py <from-ref> <to-ref> [--out DIR] [--packages core,rollups,...]
    build-destructive-manifest.py v0.16 v0.17 --out release-0.17/destructive

A source deploy adds and updates components but never deletes one, so a component a release
removes (a class, a label, a field, a record type) stays in every org that had it, keeps
counting toward the org's Apex, label and object limits, and can break a later compile
(architect review L-09, RT-06; barn-npc kept 77 stale components in October 2026).

<from-ref> is the release the org has now, <to-ref> the release being deployed (tags,
branches or commits). A component counts as removed when no package at <to-ref> has it, so a
component that moved between packages is kept. --packages limits the list to components
<from-ref> had in those package folders: name the packages the org has.

DIR (default destructive-<to-ref>) gets package.xml (empty) and destructiveChangesPost.xml.
Deploy them as Contributor Guide, CI, "Release destructive manifest" says. A removed record
type (which only Setup can delete) and a removed file whose type is not mapped are listed on
stderr, to handle by hand; the exit status is 1 when there are any.
"""

import json
import os
import re
import subprocess
import sys
from xml.sax.saxutils import escape

# Top-level folder -> (metadata type, file suffix). The member is the file name less the suffix.
FILES = {
    "classes": ("ApexClass", ".cls"),
    "triggers": ("ApexTrigger", ".trigger"),
    "pages": ("ApexPage", ".page"),
    "components": ("ApexComponent", ".component"),
    "tabs": ("CustomTab", ".tab-meta.xml"),
    "staticresources": ("StaticResource", ".resource-meta.xml"),
    "permissionsets": ("PermissionSet", ".permissionset-meta.xml"),
    "permissionsetgroups": ("PermissionSetGroup", ".permissionsetgroup-meta.xml"),
    "flexipages": ("FlexiPage", ".flexipage-meta.xml"),
    "applications": ("CustomApplication", ".app-meta.xml"),
    "layouts": ("Layout", ".layout-meta.xml"),
    "customMetadata": ("CustomMetadata", ".md-meta.xml"),
    "customPermissions": ("CustomPermission", ".customPermission-meta.xml"),
    "flows": ("Flow", ".flow-meta.xml"),
    "quickActions": ("QuickAction", ".quickAction-meta.xml"),
    "reportTypes": ("ReportType", ".reportType-meta.xml"),
    "contentassets": ("ContentAsset", ".asset-meta.xml"),
    "prompts": ("Prompt", ".prompt-meta.xml"),
    "groups": ("Group", ".group-meta.xml"),
    "notificationtypes": ("CustomNotificationType", ".notiftype-meta.xml"),
    "externalCredentials": ("ExternalCredential", ".externalCredential-meta.xml"),
    "namedCredentials": ("NamedCredential", ".namedCredential-meta.xml"),
    "remoteSiteSettings": ("RemoteSiteSetting", ".remoteSite-meta.xml"),
    "globalValueSets": ("GlobalValueSet", ".globalValueSet-meta.xml"),
    "PlatformEventSubscriberConfigs": (
        "PlatformEventSubscriberConfig", ".platformEventSubscriberConfig-meta.xml"),
}
# Folders whose members are files inside a named folder: Folder/Member.<suffix>.
FOLDERED = {
    "reports": ("Report", ".report-meta.xml", ".reportFolder-meta.xml"),
    "dashboards": ("Dashboard", ".dashboard-meta.xml", ".dashboardFolder-meta.xml"),
    "email": ("EmailTemplate", ".email-meta.xml", ".emailFolder-meta.xml"),
}
BUNDLES = {"lwc": "LightningComponentBundle", "aura": "AuraDefinitionBundle"}
# objects/<Object>/<folder>/<Name>.<kind>-meta.xml -> type; member is Object.Name.
OBJECT_CHILDREN = {
    "fields": "CustomField",
    "listViews": "ListView",
    "recordTypes": "RecordType",
    "validationRules": "ValidationRule",
    "compactLayouts": "CompactLayout",
    "webLinks": "WebLink",
    "fieldSets": "FieldSet",
    "businessProcesses": "BusinessProcess",
    "sharingReasons": "SharingReason",
}
PATH = re.compile(r"^(packages/[^/]+)/main/default/(.+)$")
LABEL = re.compile(r"<fullName>\s*([A-Za-z0-9_]+)\s*</fullName>")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def component(rest):
    """(type, member) for a path under main/default, None to skip, or "?" when not mapped."""
    parts = rest.split("/")
    top, name = parts[0], parts[-1]
    if name.startswith("."):
        return None
    if top == "labels":
        return None  # labels are read from the files' contents
    if top in BUNDLES:
        return (BUNDLES[top], parts[1]) if len(parts) > 2 else "?"
    if top == "objects":
        obj = parts[1]
        if len(parts) == 3 and name == f"{obj}.object-meta.xml":
            # A standard object cannot be deleted; only its children can.
            return ("CustomObject", obj) if "__" in obj else None
        if len(parts) == 4 and parts[2] in OBJECT_CHILDREN:
            return (OBJECT_CHILDREN[parts[2]], f"{obj}.{name.split('.')[0]}")
        return "?"
    if top in FOLDERED:
        kind, suffix, folder_suffix = FOLDERED[top]
        if len(parts) == 2 and name.endswith(folder_suffix):
            return (kind, name[: -len(folder_suffix)])  # the folder itself
        if len(parts) == 3 and name.endswith(suffix):
            return (kind, f"{parts[1]}/{name[: -len(suffix)]}")
        return None if len(parts) == 3 else "?"  # a template's body file
    if top in FILES:
        kind, suffix = FILES[top]
        if name.endswith(suffix):
            return (kind, name[: -len(suffix)])
        return None  # a body file beside its -meta.xml (.cls-meta.xml, .json, .asset)
    return "?"


def components(ref, packages=None):
    """({(type, member)}, [unmapped paths]) for the package folders at ref."""
    found, unmapped, label_files = set(), [], []
    for path in git("ls-tree", "-r", "--name-only", ref, "--", "packages").splitlines():
        match = PATH.match(path)
        if not match or (packages and os.path.basename(match.group(1)) not in packages):
            continue
        rest = match.group(2)
        if rest.startswith("labels/") and rest.endswith(".labels-meta.xml"):
            label_files.append(path)
            continue
        result = component(rest)
        if result == "?":
            unmapped.append(path)
        elif result:
            found.add(result)
    for path in label_files:
        found.update(("CustomLabel", n) for n in LABEL.findall(git("show", f"{ref}:{path}")))
    return found, unmapped


def manifest(members, version):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<Package xmlns="http://soap.sforce.com/2006/04/metadata">']
    for kind in sorted({k for k, _ in members}):
        lines.append("    <types>")
        lines += [f"        <members>{escape(m)}</members>" for k, m in sorted(members) if k == kind]
        lines.append(f"        <name>{kind}</name>")
        lines.append("    </types>")
    lines += [f"    <version>{version}</version>", "</Package>", ""]
    return "\n".join(lines)


def removed(old, new):
    """Members old has and new lacks, less the children of an object that is itself removed."""
    gone = old - new
    dropped = {m for k, m in gone if k == "CustomObject"}

    def parent(kind, member):
        if kind == "CustomMetadata":
            return member.split(".")[0] + "__mdt"
        return member.split(".")[0] if kind in OBJECT_CHILDREN.values() else None

    return {(k, m) for k, m in gone if parent(k, m) not in dropped}


def main(argv):
    args, out, packages = [], None, None
    i = 0
    while i < len(argv):
        if argv[i] in ("--out", "--packages") and i + 1 < len(argv):
            if argv[i] == "--out":
                out = argv[i + 1]
            else:
                packages = set(argv[i + 1].split(","))
            i += 2
        else:
            args.append(argv[i])
            i += 1
    if len(args) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    old_ref, new_ref = args
    root = git("rev-parse", "--show-toplevel").strip()
    os.chdir(root)
    version = json.loads(git("show", f"{new_ref}:sfdx-project.json"))["sourceApiVersion"]
    old, unmapped = components(old_ref, packages)
    new, _ = components(new_ref)
    gone = removed(old, new)
    # The Metadata API refuses to delete a record type; only Setup can (architecture.md, RT5).
    by_hand = sorted(m for k, m in gone if k == "RecordType")
    gone = {(k, m) for k, m in gone if k != "RecordType"}
    out =out or f"destructive-{re.sub(r'[^A-Za-z0-9._-]', '_', new_ref)}"
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "package.xml"), "w", encoding="utf-8") as handle:
        handle.write(manifest(set(), version))
    with open(os.path.join(out, "destructiveChangesPost.xml"), "w", encoding="utf-8") as handle:
        handle.write(manifest(gone, version))
    counts = {}
    for kind, _ in gone:
        counts[kind] = counts.get(kind, 0) + 1
    summary = ", ".join(f"{kind} {n}" for kind, n in sorted(counts.items())) or "nothing removed"
    print(f"{len(gone)} component(s) removed between {old_ref} and {new_ref}: {summary}")
    print(f"Written to {out}/package.xml and {out}/destructiveChangesPost.xml")
    still_there = set(git("ls-tree", "-r", "--name-only", new_ref, "--", "packages").splitlines())
    stale = sorted(p for p in unmapped if p not in still_there)
    for member in by_hand:
        print(f"record type {member}: deactivate and delete it in Setup (the Metadata API cannot)",
              file=sys.stderr)
    for path in stale:
        print(f"not mapped (check by hand whether {new_ref} still has it): {path}", file=sys.stderr)
    return 1 if stale or by_hand else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
