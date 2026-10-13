#!/usr/bin/env python3
"""Checks that every LWC call to an Apex method names that method's parameters (ADMIN-13).

An imperative Apex call passes one object, and the platform matches its keys to the method's
parameter names. A key the method does not have is dropped without an error, and the
parameter it was meant for arrives as null. That is how the household naming panel's Save
sent `{ settings: values }` to `saveSettings(Map<String, Object> values)` and saved nothing
(ADMIN-1), while its Jest test, whose mock accepts any shape, passed.

For each component file (tests excepted) this finds every `import name from
'@salesforce/apex/Class.method'`, every call `name({ ... })` written with an object literal,
and the keys at the top level of that literal. Each key has to be a parameter of the
@AuraEnabled method of that name in packages/*/main/default/classes/Class.cls. Calls made with
a variable rather than a literal, and wire adapters, are not checked: the literal is where the
mistake is made and where it can be read.
"""

import glob
import os
import re
import sys

LWC_GLOB = "packages/*/main/default/lwc/*/*.js"
CLASS_GLOB = "packages/*/main/default/classes/{}.cls"
IMPORT = re.compile(r"import\s+(\w+)\s+from\s+['\"]@salesforce/apex/(\w+)\.(\w+)['\"]")
METHOD = r"@AuraEnabled[^\n]*\n(?:\s*@\w+[^\n]*\n)*\s*(?:public|global)\s+static\s+[\w<>,\s.]+?\s+{}\s*\(([^)]*)\)"


def parameter_names(class_name, method):
    """The parameter names of the @AuraEnabled method, or None when it cannot be found."""
    paths = glob.glob(CLASS_GLOB.format(class_name))
    if not paths:
        return None
    source = open(paths[0], encoding="utf-8").read()
    found = re.search(METHOD.format(re.escape(method)), source)
    if not found:
        return None
    names = []
    for parameter in split_top_level(found.group(1)):
        parameter = parameter.strip()
        if parameter:
            names.append(parameter.split()[-1])
    return names


def split_top_level(text):
    """Splits on commas outside angle brackets, so Map<String, Object> stays one parameter."""
    parts, depth, current = [], 0, ""
    for char in text:
        if char == "<":
            depth += 1
        elif char == ">":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += char
    parts.append(current)
    return parts


def literal_after(source, start):
    """The object literal that opens at source[start] == '{', or None if it never closes."""
    depth = 0
    quote = None
    for index in range(start, len(source)):
        char = source[index]
        if quote:
            if char == "\\":
                continue
            if char == quote:
                quote = None
            continue
        if char in "'\"`":
            quote = char
        elif char in "{[(":
            depth += 1
        elif char in "}])":
            depth -= 1
            if depth == 0:
                return source[start + 1 : index]
    return None


def top_level_keys(literal):
    """The keys at the top level of an object literal's body: `a: 1`, `b`, `...c` skipped."""
    keys, depth, quote, current = [], 0, None, ""
    for char in literal + ",":
        if quote:
            current += char
            if char == quote:
                quote = None
            continue
        if char in "'\"`":
            quote = char
        if char in "{[(":
            depth += 1
        elif char in "}])":
            depth -= 1
        if char == "," and depth == 0:
            entry = current.strip()
            current = ""
            if not entry or entry.startswith("..."):
                if entry:
                    keys.append(None)
                continue
            match = re.match(r"['\"]?(\w+)['\"]?\s*(?::|$)", entry)
            if match:
                keys.append(match.group(1))
            continue
        current += char
    return keys


def check_file(path, cache, problems):
    source = open(path, encoding="utf-8").read()
    for local, class_name, method in IMPORT.findall(source):
        for call in re.finditer(r"(?<![\w.])" + re.escape(local) + r"\s*\(\s*\{", source):
            body = literal_after(source, call.end() - 1)
            if body is None:
                continue
            keys = top_level_keys(body)
            if None in keys:
                # A spread passes keys this check cannot see.
                continue
            signature = (class_name, method)
            if signature not in cache:
                cache[signature] = parameter_names(class_name, method)
            names = cache[signature]
            if names is None:
                continue
            line = source.count("\n", 0, call.start()) + 1
            for key in keys:
                if key not in names:
                    problems.append(
                        f"{path}:{line}: calls {class_name}.{method} with '{key}', which is not "
                        f"one of its parameters ({', '.join(names) or 'none'}), so Apex "
                        "receives null for the parameter it was meant for"
                    )


def main():
    problems = []
    cache = {}
    files = [path for path in sorted(glob.glob(LWC_GLOB)) if "__tests__" not in path]
    for path in files:
        check_file(path, cache, problems)
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-lwc-apex-params.py: FAILED, {len(problems)} problem(s) above")
        return 1
    checked = len([s for s, names in cache.items() if names is not None])
    print(f"check-lwc-apex-params.py: OK, {checked} Apex methods called with matching keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
