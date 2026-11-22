#!/usr/bin/env python3
"""Stages the project with leading indentation removed from every Apex class and trigger.

Salesforce counts every character of Apex but comments against the org's 6,000,000 character
limit, and indentation is characters. The repository keeps Apex formatted (tabs, ADR-0241
"Strip Apex indentation at deploy time"); only the copy sent to an org or into a package
version loses the leading spaces and tabs on each line. Newlines stay, so a line number in a
stack trace is the line number in the repository source. Code viewed in Setup appears without
indentation.

    python3 scripts/packaging/strip-apex-indent.py --stage DIR [--root REPO]
    python3 scripts/packaging/strip-apex-indent.py --measure [--root REPO]

--stage copies sfdx-project.json, .forceignore and every package directory named in
sfdx-project.json into DIR, with the paths unchanged, so `sf` can run from DIR. Every .cls and
.trigger file loses its leading whitespace; every other file, -meta.xml files included, is
copied byte for byte. --measure prints the characters the stripping saves.

Leading whitespace inside a string literal is never touched. An Apex string cannot span lines,
so a line that starts inside one only happens in source that does not compile; such a line is
left exactly as written. Block comments are stripped like code.
"""

import argparse
import json
import os
import shutil
import sys

APEX_SUFFIXES = (".cls", ".trigger")
ROOT_FILES = ("sfdx-project.json", ".forceignore")


def strip_indent(text):
    """text with the spaces and tabs at the start of every line removed, newlines kept.

    A line is left alone when it starts inside a string literal (a backslash before the
    newline, or an unterminated quote). Comments and strings are tracked so a quote inside a
    comment does not count.
    """
    out = []
    i, n = 0, len(text)
    state = "code"  # code | line | block | string
    at_line_start = True
    while i < n:
        if at_line_start:
            at_line_start = False
            if state != "string":
                while i < n and text[i] in " \t":
                    i += 1
                if i >= n:
                    break
        c = text[i]
        if c == "\n":
            out.append(c)
            i += 1
            at_line_start = True
            if state == "line":
                state = "code"
            continue
        if state == "code":
            if text.startswith("//", i):
                state = "line"
            elif text.startswith("/*", i):
                state = "block"
                out.append("/*")
                i += 2
                continue
            elif c == "'":
                state = "string"
        elif state == "block":
            if text.startswith("*/", i):
                state = "code"
                out.append("*/")
                i += 2
                continue
        elif state == "string":
            if c == "\\" and i + 1 < n and text[i + 1] != "\n":
                out.append(text[i : i + 2])
                i += 2
                continue
            if c == "'":
                state = "code"
        out.append(c)
        i += 1
    return "".join(out)


def strip_bytes(data):
    return strip_indent(data.decode("utf-8")).encode("utf-8")


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def package_paths(root):
    with open(os.path.join(root, "sfdx-project.json"), encoding="utf-8") as handle:
        return [entry["path"] for entry in json.load(handle)["packageDirectories"]]


def _copy(src, dest, stats):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.islink(src):
        os.symlink(os.readlink(src), dest)
        return
    if src.endswith(APEX_SUFFIXES):
        with open(src, "rb") as handle:
            raw = handle.read()
        stripped = strip_bytes(raw)
        with open(dest, "wb") as handle:
            handle.write(stripped)
        shutil.copystat(src, dest)
        stats["apex_files"] += 1
        stats["saved"] += len(raw.decode("utf-8")) - len(stripped.decode("utf-8"))
    else:
        shutil.copy2(src, dest)
        stats["other_files"] += 1


def stage(root, dest):
    """Copy the project into dest with Apex indentation removed. Returns counts."""
    stats = {"apex_files": 0, "other_files": 0, "saved": 0}
    os.makedirs(dest, exist_ok=True)
    for name in ROOT_FILES:
        if os.path.exists(os.path.join(root, name)):
            _copy(os.path.join(root, name), os.path.join(dest, name), stats)
    for rel in package_paths(root):
        base = os.path.join(root, rel)
        for folder, dirs, files in os.walk(base):
            dirs.sort()
            for name in sorted(files):
                src = os.path.join(folder, name)
                _copy(src, os.path.join(dest, os.path.relpath(src, root)), stats)
    return stats


def measure(root):
    """Characters saved by stripping, over every Apex file in the package directories."""
    saved = 0
    for rel in package_paths(root):
        for folder, _dirs, files in os.walk(os.path.join(root, rel)):
            for name in files:
                if name.endswith(APEX_SUFFIXES):
                    with open(os.path.join(folder, name), "rb") as handle:
                        text = handle.read().decode("utf-8")
                    saved += len(text) - len(strip_indent(text))
    return saved


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=repo_root(), help="the repository (default: this one)")
    parser.add_argument("--stage", metavar="DIR", help="copy the project into DIR, Apex stripped")
    parser.add_argument("--measure", action="store_true", help="print the characters stripping saves")
    args = parser.parse_args(argv)
    if bool(args.stage) == bool(args.measure):
        parser.error("give exactly one of --stage and --measure")
    if args.measure:
        print(measure(args.root))
        return 0
    stats = stage(args.root, args.stage)
    print(
        f"Staged {stats['apex_files']} Apex files without indentation ({stats['saved']:,} characters"
        f" saved) and {stats['other_files']} other files in {args.stage}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
