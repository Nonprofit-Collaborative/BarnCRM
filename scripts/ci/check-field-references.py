#!/usr/bin/env python3
"""Gate: every reference to one of BarnCRM's own custom fields or objects names one that exists.

Why this exists
---------------
A field removed from the repo stays in every org it was ever deployed to. The dev gate orgs
(oi-test, barn-sales) keep it, so a SELECT that still names it compiles there and the gates
pass; only a clean org (barn-npc) or an offline check sees the compile error. #666 removed
`Integration_App__mdt.Install_Url__c` (D-138) and #681 brought it back into a SOQL SELECT;
the gates stayed green and the check-only deploy to barn-npc failed. This check is the
offline half of that guard.

What counts as a reference
--------------------------
A custom name is `Name__c`, `Name__mdt`, `Name__e` or a relationship `Name__r`. A namespaced
name (`npsp__Name__c`, `GW_Volunteers__Name__c`) belongs to another package and is skipped.

  Apex (*.cls, *.trigger)  comments and string literals are removed first, so only
                           compile-time references are checked.
  JavaScript (lwc *.js)    `@salesforce/schema/...` imports, and string literals that are
                           exactly `Object.Field__c` for an object the repo defines.
  HTML (lwc *.html)        `field-name` and `object-api-name` attribute values.
  Metadata (*.xml)         prose (label, description, help text, values) and comments are
                           removed; custom metadata record fields are checked against their
                           type.

The index is every `objects/<Object>/` folder under packages/ and every
`objects/<Object>/fields/<Field>.field-meta.xml`, across all packages.

Rules
-----
1. `Object.Field__c` (or `Object.Rel__r`) where Object is defined in the repo: the field must
   be on that object. A standard object counts when the repo adds a field to it.
2. A SOQL query `[SELECT ... FROM Object ...]` on a repo object: every bare custom field in it
   must be on that object. Subqueries are checked against their own FROM.
3. Any other custom name: an unnamespaced `__c` must be a repo object or a field on some repo
   object; `__mdt` and `__e` must be repo objects; `__r` must be a repo lookup field (`__c`)
   or a child relationship name. Sharing reasons and report types (`Gifts__c`) count as
   defined names. Fields on objects the repo does not define (`GiftTransaction.X__c`, a
   SOQL query FROM an NPC object) are never checked, since they cannot be told apart from
   another package's or the org's own.

Exceptions go in scripts/ci/field-references-allowlist.txt as `path token  # reason`.

Exit code 1 on any unknown reference.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apex_source import strip  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ALLOWLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "field-references-allowlist.txt")

# An unnamespaced custom name: no "__" before the suffix.
CUSTOM = re.compile(r"(?<![\w$])((?:[A-Za-z0-9]|_(?!_))+)__(c|mdt|e|r)\b")
QUALIFIED = re.compile(r"(?<![\w.$])([A-Za-z]\w*)\.((?:[A-Za-z0-9]|_(?!_))+__[cr])\b")

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
    "helpText",
    "content",
)
PROSE = re.compile(r"<(%s)\b[^>]*>.*?</\1>" % "|".join(PROSE_TAGS), re.DOTALL)
XML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
SCHEMA_IMPORT = re.compile(r"""['"]@salesforce/schema/([^'"]+)['"]""")
HTML_ATTR = re.compile(r"""\b(?:field-name|object-api-name)\s*=\s*["']([^"'{}]+)["']""")
JS_STRING = re.compile(r"""(['"`])((?:\\.|(?!\1).)*)\1""")
CMD_FIELD = re.compile(r"<field>\s*([\w]+)\s*</field>")


class Index:
    """Objects and fields the repo defines, keyed case-insensitively."""

    def __init__(self, objects, relationships=(), other_names=()):
        # objects: {object name: iterable of field names}
        # relationships: child relationship names (`Gift_Allocations__r`)
        # other_names: other custom-suffixed names the repo defines, such as sharing reasons
        # (`Shared_With_Find_Users__c`) and report types (`Gifts__c`)
        self.names = {name.lower(): name for name in objects}
        self.fields = {name.lower(): {f.lower() for f in fields} for name, fields in objects.items()}
        self.all_fields = set().union(*self.fields.values()) if self.fields else set()
        self.relationships = {r.lower() for r in relationships}
        self.other_names = {n.lower() for n in other_names}

    def has_object(self, name):
        return name.lower() in self.names

    def object_has(self, obj, field):
        field = field.lower()
        if field.endswith("__r"):
            if field in self.relationships:
                return True  # a child relationship; its owning lookup is on the child object
            field = field[:-3] + "__c"
        return field in self.fields.get(obj.lower(), set())

    def known(self, token):
        """Rule 3: whether an unqualified custom name exists somewhere."""
        low = token.lower()
        if low.endswith("__c"):
            return low in self.names or low in self.all_fields or low in self.other_names
        if low.endswith(("__mdt", "__e")):
            return low in self.names
        if low.endswith("__r"):
            return low[:-3] + "__c" in self.all_fields or low in self.relationships
        return True


RELATIONSHIP_NAME = re.compile(r"<relationshipName>\s*(\w+)\s*</relationshipName>")


def build_index(root):
    objects = {}
    relationships = set()
    other_names = set()
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = [d for d in subdirs if d not in ("node_modules", "__tests__")]
        parts = directory.replace(os.sep, "/").split("/")
        if len(parts) >= 2 and parts[-2] == "objects":
            objects.setdefault(parts[-1], set())
        for name in files:
            if name.endswith(".sharingReason-meta.xml"):
                other_names.add(name[: -len(".sharingReason-meta.xml")])
            elif name.endswith(".reportType-meta.xml"):
                other_names.add(name[: -len(".reportType-meta.xml")] + "__c")
        if len(parts) >= 3 and parts[-1] == "fields" and parts[-3] == "objects":
            for name in files:
                if name.endswith(".field-meta.xml") and " 2." not in name:
                    objects.setdefault(parts[-2], set()).add(name[: -len(".field-meta.xml")])
                    with open(os.path.join(directory, name), encoding="utf-8") as handle:
                        relationships.update(m + "__r" for m in RELATIONSHIP_NAME.findall(handle.read()))
    return Index(objects, relationships, other_names)


def _blank(match):
    return re.sub(r"[^\n]", " ", match.group(0))


def _line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def _qualified(index, text):
    """Rule 1 over text: yield (offset, token) for Object.Field__c not on Object."""
    for match in QUALIFIED.finditer(text):
        obj, field = match.group(1), match.group(2)
        if index.has_object(obj) and not index.object_has(obj, field):
            yield match.start(2), "%s.%s" % (obj, field)


def foreign_offsets(index, text):
    """Offsets of fields named on an object the repo does not define (`GiftTransaction.X__c`).

    The qualifier must look like a type (capitalized, not a relationship); a lower-case
    qualifier is a variable, whose field rule 3 still checks.
    """
    skip = set()
    for match in QUALIFIED.finditer(text):
        obj = match.group(1)
        if obj[0].isupper() and not index.has_object(obj) and not CUSTOM.fullmatch(obj):
            skip.add(match.start(2))
    return skip


def _unqualified(index, text, skip=frozenset()):
    """Rule 3 over text: yield (offset, token) for custom names that exist nowhere."""
    skip = set(skip) | foreign_offsets(index, text)
    for match in CUSTOM.finditer(text):
        token = match.group(0)
        if match.start() not in skip and not index.known(token):
            yield match.start(), token


# --- SOQL (rule 2) ---------------------------------------------------------------------------

FROM = re.compile(r"\bFROM\s+(\w+)", re.IGNORECASE)
SELECT_START = re.compile(r"\[\s*SELECT\b", re.IGNORECASE)
BARE = re.compile(r"(?<![\w.:$])((?:[A-Za-z0-9]|_(?!_))+__[cr])\b")


def _matching(text, start, open_char, close_char):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_char:
            depth += 1
        elif text[i] == close_char:
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def _soql_scope(index, text, base, out, skip):
    """Check one SELECT (text at absolute offset base); nested SELECTs recurse.

    A query on a repo object adds each unknown bare field to out. A query on a standard
    object the repo does not define adds its bare fields to skip, so rule 3 leaves them alone.
    """
    flat = list(text)
    i = 0
    while True:
        at = text.find("(", i)
        if at < 0:
            break
        end = _matching(text, at, "(", ")")
        inner = text[at + 1 : end]
        if re.match(r"\s*SELECT\b", inner, re.IGNORECASE):
            _soql_scope(index, inner, base + at + 1, out, skip)
            flat[at : end + 1] = " " * (end + 1 - at)
            i = end + 1
        else:
            i = at + 1
    body = "".join(flat)
    source = FROM.search(body)
    if not source:
        return
    obj = source.group(1)
    if not index.has_object(obj):
        if not CUSTOM.fullmatch(obj):
            skip.update(base + m.start(1) for m in BARE.finditer(body))
        return
    for match in BARE.finditer(body):
        field = match.group(1)
        if field.lower() != obj.lower() and not index.object_has(obj, field):
            out[base + match.start(1)] = "%s.%s" % (obj, field)


def soql_findings(index, code):
    """Rule 2 over Apex code: ({offset: token} of misplaced fields, offsets rule 3 skips)."""
    out, skip = {}, set()
    for match in SELECT_START.finditer(code):
        end = _matching(code, match.start(), "[", "]")
        _soql_scope(index, code[match.start() + 1 : end], match.start() + 1, out, skip)
    return out, skip


# --- per file type ---------------------------------------------------------------------------


def apex_refs(index, text):
    code = strip(text)
    found, skip = soql_findings(index, code)
    return _combine(index, text, code, found, skip)


def _combine(index, text, code, found, skip=frozenset()):
    """Add rules 1 and 3 to found ({offset: token}); one finding per offset, as (line, token)."""
    for offset, token in _qualified(index, code):
        found.setdefault(offset, token)
    for offset, token in _unqualified(index, code, skip):
        found.setdefault(offset, token)
    return [(_line_of(text, o), t) for o, t in sorted(found.items())]


JS_COMMENT = re.compile(r"/\*.*?\*/|(?<![:\\'\"])//[^\n]*", re.DOTALL)


def js_refs(index, text):
    code = JS_COMMENT.sub(_blank, text)
    refs = []
    for match in SCHEMA_IMPORT.finditer(code):
        path = match.group(1)
        offset = match.start(1)
        obj, _, rest = path.partition(".")
        if not CUSTOM.fullmatch(obj) and not index.has_object(obj):
            continue
        if not index.known(obj) and CUSTOM.fullmatch(obj):
            refs.append((_line_of(text, offset), obj))
            continue
        first = rest.split(".")[0] if rest else ""
        if first and CUSTOM.fullmatch(first) and index.has_object(obj) and not index.object_has(obj, first):
            refs.append((_line_of(text, offset), "%s.%s" % (obj, first)))
    for match in JS_STRING.finditer(code):
        value = match.group(2)
        if "@salesforce/" in value:
            continue
        qualified = re.fullmatch(r"([A-Za-z]\w*)\.(\w+__[cr])", value)
        if qualified and index.has_object(qualified.group(1)):
            if not index.object_has(qualified.group(1), qualified.group(2)):
                refs.append((_line_of(text, match.start(2)), value))
    return refs


def html_refs(index, text):
    refs = []
    for match in HTML_ATTR.finditer(text):
        for offset, token in _qualified(index, match.group(1)):
            refs.append((_line_of(text, match.start(1)), token))
        for offset, token in _unqualified(index, match.group(1)):
            refs.append((_line_of(text, match.start(1)), token))
    return refs


def xml_refs(index, text, cmd_type=None):
    stripped = PROSE.sub(_blank, XML_COMMENT.sub(_blank, text))
    found = {}
    if cmd_type:
        for match in CMD_FIELD.finditer(stripped):
            if not index.object_has(cmd_type, match.group(1)):
                found[match.start(1)] = "%s.%s" % (cmd_type, match.group(1))
        stripped = CMD_FIELD.sub(_blank, stripped)
    return _combine(index, text, stripped, found)


def file_refs(index, rel, text):
    """References in one file, as (line, token). rel is a /-separated repo path."""
    parts = rel.split("/")
    name = parts[-1]
    if name.endswith((".cls", ".trigger")):
        return apex_refs(index, text)
    if "lwc" in parts and name.endswith(".js") and not name.endswith(".test.js"):
        return js_refs(index, text)
    if "lwc" in parts and name.endswith(".html"):
        return html_refs(index, text)
    if name.endswith(".md-meta.xml") and "customMetadata" in parts:
        return xml_refs(index, text, cmd_type=name.split(".")[0] + "__mdt")
    if name.endswith(".xml"):
        return xml_refs(index, text)
    return []


def load_allowlist(path=ALLOWLIST):
    allowed = set()
    if not os.path.exists(path):
        return allowed
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.split("#", 1)[0].strip()
            if line:
                rel, token = line.split()
                allowed.add((rel, token))
    return allowed


def scan(root, index, allowed=frozenset()):
    findings = []
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = sorted(d for d in subdirs if d not in ("node_modules", "__tests__", ".sfdx", ".sf"))
        for name in sorted(files):
            if " 2." in name:
                continue  # sync-duplicate copies are not tracked source
            path = os.path.join(directory, name)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if not name.endswith((".cls", ".trigger", ".js", ".html", ".xml")):
                continue
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            lines = text.split("\n")
            for number, token in file_refs(index, rel, text):
                if (rel, token) in allowed:
                    continue
                findings.append("%s:%d: %s (%s)" % (rel, number, lines[number - 1].strip(), token))
    return findings


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages")
    index = build_index(os.path.join(ROOT, "packages"))
    findings = scan(root, index, load_allowlist())
    if findings:
        for entry in findings:
            print(entry)
        sys.stdout.flush()
        print(
            "FAIL: reference(s) above name a custom field or object that no package defines.\n"
            "  The dev gate orgs still hold removed fields, so only this check or a clean org\n"
            "  catches it. Remove the reference, or add `path token  # reason` to\n"
            "  scripts/ci/field-references-allowlist.txt.",
            file=sys.stderr,
        )
        print("check-field-references.py: FAILED", file=sys.stderr)
        return 1
    print("check-field-references.py: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
