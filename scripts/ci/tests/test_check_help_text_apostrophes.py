import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "check_help_text_apostrophes", os.path.join(HERE, "..", "check-help-text-apostrophes.py")
)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

CATALOGS = {
    "Mirror": {
        "Lone": "The mirror's run has not finished since {0}.",
        "Doubled": "The mirror''s run has not finished since {0}.",
        "Plain": "Nothing to see since {0}.",
    }
}


class CheckHelpTextApostrophesTest(unittest.TestCase):
    def test_a_lone_apostrophe_read_through_string_format_fails(self):
        problems = check.check(
            {"A.cls": "class A {\n String s = String.format(\n BarnHelp.text('Mirror', 'Lone'), args); }"},
            CATALOGS,
        )
        self.assertEqual(1, len(problems))
        self.assertIn("A.cls:2", problems[0])
        self.assertIn("Mirror.Lone", problems[0])

    def test_a_lone_apostrophe_read_with_arguments_fails(self):
        problems = check.check(
            {"B.cls": "class B { String s = BarnHelp.text('Mirror', 'Lone', new List<Object>{ 1 }); }"},
            CATALOGS,
        )
        self.assertEqual(1, len(problems))

    def test_a_baselined_defect_is_skipped(self):
        problems = check.check(
            {"D.cls": "class D { String s = BarnHelp.text('Mirror', 'Lone', args); }"},
            CATALOGS,
            {"Mirror.Lone"},
        )
        self.assertEqual([], problems)

    def test_doubled_plain_and_unformatted_texts_pass(self):
        problems = check.check(
            {
                "C.cls": "class C { String a = BarnHelp.text('Mirror', 'Doubled', args);"
                " String b = BarnHelp.text('Mirror', 'Plain', args);"
                " String c = BarnHelp.text('Mirror', 'Lone'); }"
            },
            CATALOGS,
        )
        self.assertEqual([], problems)


if __name__ == "__main__":
    unittest.main()
