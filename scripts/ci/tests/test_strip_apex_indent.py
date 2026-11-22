"""strip-apex-indent.py: leading whitespace goes, everything else stays (AP-05)."""

import importlib.util
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "scripts", "ci"))

spec = importlib.util.spec_from_file_location(
    "strip_apex_indent", os.path.join(REPO, "scripts", "packaging", "strip-apex-indent.py")
)
strip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strip)
from apex_source import without_comments  # noqa: E402

FIXTURE = (
    "public with sharing class Sample {\n"
    "\t/**\n"
    "\t * A block comment.\n"
    "\t   Indented continuation with 'a quote.\n"
    "\t */\n"
    "\tpublic static String greet(String name) {\n"
    "\t\tString a = '  two leading spaces after the quote';\n"
    "\t\tString b = 'it\\'s \\\\' + '\ttab after quote';\n"
    "\t\t// a comment with 'an apostrophe\n"
    "\t\treturn a + b;   \n"
    "\t}\n"
    "\n"
    "   \t \n"
    "}\n"
)


class StripIndentTest(unittest.TestCase):
    def test_removes_leading_tabs_and_spaces_only(self):
        self.assertEqual(
            strip.strip_indent(FIXTURE),
            "public with sharing class Sample {\n"
            "/**\n"
            "* A block comment.\n"
            "Indented continuation with 'a quote.\n"
            "*/\n"
            "public static String greet(String name) {\n"
            "String a = '  two leading spaces after the quote';\n"
            "String b = 'it\\'s \\\\' + '\ttab after quote';\n"
            "// a comment with 'an apostrophe\n"
            "return a + b;   \n"
            "}\n"
            "\n"
            "\n"
            "}\n",
        )

    def test_line_numbers_are_unchanged(self):
        out = strip.strip_indent(FIXTURE)
        self.assertEqual(out.count("\n"), FIXTURE.count("\n"))
        for before, after in zip(FIXTURE.split("\n"), out.split("\n")):
            self.assertEqual(before.lstrip(" \t"), after)

    def test_quote_in_comment_does_not_open_a_string(self):
        text = "  // it's\n    x = 1;\n  /* don't */\n    y = 2;\n"
        self.assertEqual(strip.strip_indent(text), "// it's\nx = 1;\n/* don't */\ny = 2;\n")

    def test_line_starting_inside_a_string_is_left_alone(self):
        text = "x = 'abc\\\n    def';\n    y = 1;\n"
        self.assertEqual(strip.strip_indent(text), "x = 'abc\\\n    def';\ny = 1;\n")

    def test_is_idempotent_and_keeps_crlf(self):
        once = strip.strip_indent(FIXTURE.replace("\n", "\r\n"))
        self.assertEqual(strip.strip_indent(once), once)
        self.assertEqual(once.count("\r\n"), FIXTURE.count("\n"))

    def test_counted_size_drops_by_the_indentation_of_code(self):
        before = without_comments(FIXTURE)
        saved = len(before) - len(without_comments(strip.strip_indent(FIXTURE)))
        indent = sum(len(line) - len(line.lstrip(" \t")) for line in before.split("\n"))
        self.assertGreater(saved, 0)
        self.assertEqual(saved, indent)


class StageTest(unittest.TestCase):
    def test_stage_strips_apex_and_copies_everything_else_byte_for_byte(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, dest = os.path.join(tmp, "repo"), os.path.join(tmp, "stage")
            files = {
                "sfdx-project.json": json.dumps({"packageDirectories": [{"path": "packages/core"}]}),
                ".forceignore": "**/.gitkeep\n",
                "packages/core/main/default/classes/A.cls": FIXTURE,
                "packages/core/main/default/classes/A.cls-meta.xml": "\t<ApexClass>\n\t\t<x/>\n</ApexClass>\n",
                "packages/core/main/default/triggers/T.trigger": "\ttrigger T on Account (before insert) {\n\t}\n",
                "packages/core/main/default/lwc/x.js": "\tconst a = 1;\n",
                "packages/other/B.cls": "    class B {}\n",
            }
            for rel, body in files.items():
                path = os.path.join(root, rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8", newline="") as handle:
                    handle.write(body)
            stats = strip.stage(root, dest)
            self.assertEqual(stats["apex_files"], 2)
            self.assertEqual(stats["saved"], strip.measure(root))
            for rel, body in files.items():
                staged = os.path.join(dest, rel)
                if rel.startswith("packages/other"):
                    self.assertFalse(os.path.exists(staged), "only package directories are staged")
                    continue
                with open(staged, encoding="utf-8", newline="") as handle:
                    text = handle.read()
                if rel.endswith((".cls", ".trigger")):
                    self.assertEqual(text, strip.strip_indent(body))
                else:
                    self.assertEqual(text, body, rel)

    def test_repo_apex_stages_and_the_saving_is_large(self):
        self.assertGreater(strip.measure(REPO), 100_000)


if __name__ == "__main__":
    unittest.main()
