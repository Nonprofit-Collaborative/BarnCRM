#!/usr/bin/env python3
"""Fails when a Lightning web component adds a look the suite visual standard replaced.

The standard (docs/contributor-guide/ux-kit.md, Visual Standard) gives each job one kit part.
This check flags the old one-offs in component markup and JavaScript (Jest tests skipped):

- title-caps     `slds-text-title_caps` (ALL CAPS); use `slds-text-title_bold`.
- solid-box      `slds-box` with `slds-theme_error|warning|success`; use `c-barn-notice`.
- table-stacked  a `<table>` with `slds-table` but no `slds-max-medium-table_stacked` (or another
                 `_stacked` class), so it overflows a phone. A deliberately wide table inside
                 `slds-scrollable_x` (an import preview) carries the `data-wide-table` attribute.
- badge-inverse  `slds-badge_inverse`; the status vocabulary never uses a black badge
                 (`c-barn-status-badge status="neutral"`).
- card-utility   a `lightning-card` header icon from the `utility:` set; card headers use the
                 page's tab icon (`custom:` or `standard:`, c/barnIcons).

Screens built before the standard are listed in visual-standard-baseline.txt with a count per
rule. A count above the baseline (or a file not in it) fails; a count below it passes and is
reported, so the rollout can lower the baseline without branches colliding on it. Regenerate
it with `--write-baseline` only when lowering it.
"""

import glob
import os
import re
import sys

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "visual-standard-baseline.txt")

TAG = re.compile(r"<([a-zA-Z][\w-]*)\b([^>]*)>", re.S)
CLASS = re.compile(r'\bclass\s*=\s*"([^"]*)"')


def classes(attrs):
    match = CLASS.search(attrs)
    return match.group(1).split() if match else []


def html_hits(text):
    hits = []
    for tag in TAG.finditer(text):
        name, attrs = tag.group(1).lower(), tag.group(2)
        found = classes(attrs)
        if "slds-text-title_caps" in found:
            hits.append("title-caps")
        if "slds-box" in found and any(c in found for c in ("slds-theme_error", "slds-theme_warning", "slds-theme_success")):
            hits.append("solid-box")
        if name == "table" and "slds-table" in found:
            stacked = any(c.endswith("_stacked") or "_stacked-" in c for c in found)
            if not stacked and "data-wide-table" not in attrs:
                hits.append("table-stacked")
        if "slds-badge_inverse" in found:
            hits.append("badge-inverse")
        if name == "lightning-card" and re.search(r'\bicon-name\s*=\s*"utility:', attrs):
            hits.append("card-utility")
    return hits


def js_hits(text):
    return ["badge-inverse"] * len(re.findall(r"slds-badge_inverse", text))


def scan():
    counts = {}
    paths = glob.glob("packages/*/main/default/lwc/*/*.html") + glob.glob("packages/*/main/default/lwc/*/*.js")
    for path in sorted(paths):
        if "/__tests__/" in path:
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for rule in html_hits(text) if path.endswith(".html") else js_hits(text):
            counts[(path, rule)] = counts.get((path, rule), 0) + 1
    return counts


def read_baseline():
    baseline = {}
    if not os.path.isfile(BASELINE):
        return baseline
    with open(BASELINE, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            path, rule, count = line.split()
            baseline[(path, rule)] = int(count)
    return baseline


def write_baseline(counts):
    lines = [
        "# Screens built before the visual standard: path rule count (scripts/ci/check-visual-standard.py).",
        "# Lower a count, or delete a line, when a screen adopts the kit. Never raise one.",
    ]
    lines += [f"{path} {rule} {count}" for (path, rule), count in sorted(counts.items())]
    with open(BASELINE, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    counts = scan()
    if "--write-baseline" in sys.argv[1:]:
        write_baseline(counts)
        print(f"check-visual-standard.py: baseline written, {len(counts)} entries")
        return 0
    baseline = read_baseline()
    problems = []
    for key, count in sorted(counts.items()):
        allowed = baseline.get(key, 0)
        if count > allowed:
            path, rule = key
            problems.append(f"{path}: {rule} {count} time(s), baseline {allowed}")
    lowered = [key for key, allowed in baseline.items() if counts.get(key, 0) < allowed]
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-visual-standard.py: FAILED, {len(problems)} new one-off look(s) above. Use the kit part "
            "named in docs/contributor-guide/ux-kit.md (Visual Standard).",
            file=sys.stderr,
        )
        return 1
    note = f"; {len(lowered)} baseline entries can be lowered (--write-baseline)" if lowered else ""
    print(f"check-visual-standard.py: OK, {sum(baseline.values())} baseline one-offs left{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
