#!/usr/bin/env python3
"""Gate: no compile-time or deploy-time reference to a Person Account field.

Why this exists
---------------
Core must install on an org without Person Accounts (ADR-0013), and every package must
install on one too. `IsPersonAccount`, `PersonEmail`, `PersonMailingPostalCode` and the
`__pc` / `__pr` fields exist only where Person Accounts are on, so a static reference to one
(`Account.PersonEmail`, `[SELECT PersonEmail FROM Account]`, a permission set granting
`Account.PersonEmail`) is a compile or deploy error that refuses the whole package.
`check-standard-objects.sh` denies `IsPersonAccount` in Core and the modules only, and
`check-object-allowlist.py` sees objects, not fields, so before this check review was the
only guard (docs/contributor-guide/dynamic-apex.md, sections 1 and 2).

The allowed seam
----------------
A Person Account field is reached by name, as text, and resolved through the org's own
describe at runtime: a `String` constant, a dynamic SOQL string, `record.get('PersonEmail')`
(`ImportMatcher`, `AddressService`, `PersonRecordSelector`). Text is never a reference, so:

  Apex (*.cls, *.trigger)  comments and string literals are removed, then any field name
                           left is a failure.
  JavaScript (lwc *.js)    only `@salesforce/schema/...` imports are references; a field
                           name there is a failure.
  HTML (lwc *.html)        a `field-name="..."` naming one is a failure.
  Metadata (*.xml)         prose (label, description, help text, values) is removed, then
                           any field name left is a failure. Custom metadata records are
                           data, not references, and are skipped like
                           check-standard-objects.sh skips import template headings.

There is no exemption marker. The `// detection-only:` marker `check-standard-objects.sh`
honors exists for string constants, which this check already accepts; anything it would
still find is a compile-time reference, which no marker makes safe.

The vendored rollup engine (packages/*/vendor) is third party source and is not scanned.

Exit code 1 on any reference found.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACKAGES = os.path.join(ROOT, "packages")

# The standard Person Account fields on Account, and every custom person field (__pc) and
# its relationship (__pr). Whole words, case-sensitive like Apex field tokens in this repo.
PERSON_FIELD = re.compile(
    r"\b(?:IsPersonAccount"
    r"|Person(?:ContactId|Contact|Email|EmailBounced\w+|HasOptedOutOf\w+|DoNotCall"
    r"|Birthdate|Title|Department|Assistant\w+|HomePhone|MobilePhone|OtherPhone"
    r"|LeadSource|LastCU\w+|IndividualId|Individual|Pronouns|GenderIdentity"
    r"|Mailing\w+|Other\w+|ActionCadence\w*)"
    r"|\w+__p[cr])\b"
)

PROSE_TAGS = (
    "description",
    "label",
    "inlineHelpText",
    "masterLabel",
    "pluralLabel",
    "errorMessage",
    "shortDescription",
    "value",
    "fullDescription",
)
PROSE = re.compile(r"<(%s)\b[^>]*>.*?</\1>" % "|".join(PROSE_TAGS), re.DOTALL)
XML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
SCHEMA_IMPORT = re.compile(r"""['"]@salesforce/schema/([^'"]+)['"]""")
FIELD_NAME_ATTR = re.compile(r"""\bfield-name\s*=\s*["']([^"']+)["']""")


def strip_apex(source):
    """Blanks comments and string literals, keeping line breaks so line numbers hold."""
    out = []
    i = 0
    n = len(source)
    while i < n:
        c = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            while i < n and source[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and nxt == "*":
            out.append("  ")
            i += 2
            while i < n and not (source[i] == "*" and i + 1 < n and source[i + 1] == "/"):
                out.append("\n" if source[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
        elif c == "'":
            out.append(" ")
            i += 1
            while i < n and source[i] != "'":
                if source[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if source[i] == "\n" else " ")
                i += 1
            out.append(" ")
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def apex_findings(path, text):
    findings = []
    raw_lines = text.split("\n")
    for number, line in enumerate(strip_apex(text).split("\n"), start=1):
        name = PERSON_FIELD.search(line)
        if name:
            findings.append(
                "%s:%d: %s (%s)" % (path, number, raw_lines[number - 1].strip(), name.group(0))
            )
    return findings


def js_findings(path, text):
    findings = []
    for number, line in enumerate(text.split("\n"), start=1):
        for match in SCHEMA_IMPORT.finditer(line):
            name = PERSON_FIELD.search(match.group(1))
            if name:
                findings.append("%s:%d: %s (%s)" % (path, number, line.strip(), name.group(0)))
    return findings


def html_findings(path, text):
    findings = []
    for number, line in enumerate(text.split("\n"), start=1):
        for match in FIELD_NAME_ATTR.finditer(line):
            name = PERSON_FIELD.search(match.group(1))
            if name:
                findings.append("%s:%d: %s (%s)" % (path, number, line.strip(), name.group(0)))
    return findings


def xml_findings(path, text):
    findings = []

    def blank(match):
        return re.sub(r"[^\n]", " ", match.group(0))

    stripped = PROSE.sub(blank, XML_COMMENT.sub(blank, text))
    raw_lines = text.split("\n")
    for number, line in enumerate(stripped.split("\n"), start=1):
        name = PERSON_FIELD.search(line)
        if name:
            findings.append(
                "%s:%d: %s (%s)" % (path, number, raw_lines[number - 1].strip(), name.group(0))
            )
    return findings


def scan(root):
    findings = []
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = sorted(d for d in subdirs if d not in ("vendor", "node_modules", "__tests__"))
        parts = directory.replace(os.sep, "/").split("/")
        for name in sorted(files):
            if " 2." in name:
                continue  # sync-duplicate copies are not tracked source
            path = os.path.join(directory, name)
            rel = os.path.relpath(path, ROOT)
            if name.endswith((".cls", ".trigger")):
                with open(path, encoding="utf-8") as handle:
                    findings += apex_findings(rel, handle.read())
            elif name.endswith(".js") and "lwc" in parts:
                with open(path, encoding="utf-8") as handle:
                    findings += js_findings(rel, handle.read())
            elif name.endswith(".html") and "lwc" in parts:
                with open(path, encoding="utf-8") as handle:
                    findings += html_findings(rel, handle.read())
            elif name.endswith(".xml") and "customMetadata" not in parts:
                with open(path, encoding="utf-8") as handle:
                    findings += xml_findings(rel, handle.read())
    return findings


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else PACKAGES
    findings = scan(root)
    if findings:
        for entry in findings:
            print(entry)
        print(
            "FAIL: Person Account field reference(s) found above. Hold the name as a String\n"
            "  and resolve it through describe (docs/contributor-guide/dynamic-apex.md).",
            file=sys.stderr,
        )
        print("check-person-account-fields.py: FAILED", file=sys.stderr)
        return 1
    print("check-person-account-fields.py: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
