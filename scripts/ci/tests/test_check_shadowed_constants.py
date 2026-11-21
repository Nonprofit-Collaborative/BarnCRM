import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "check_shadowed_constants", os.path.join(HERE, "..", "check-shadowed-constants.py")
)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

PATH = "packages/x/main/default/classes/Foo.cls"


def problems(body):
    source = "public class Foo {\n\tprivate static final String DRAFT = 'Draft';\n" + body + "\n}"
    return check.problems_in_source(PATH, source, set())


class CheckShadowedConstantsTest(unittest.TestCase):
    def test_a_local_read_as_the_constant_later_fails(self):
        found = problems("\tvoid f() {\n\t\tMap<String, Object> draft = new Map<String, Object>();\n\t\tg(DRAFT);\n\t}")
        self.assertEqual(1, len(found))
        self.assertIn("Foo.cls:4", found[0])
        self.assertIn("hides the constant DRAFT", found[0])

    def test_a_parameter_read_as_the_constant_fails(self):
        self.assertEqual(1, len(problems("\tvoid f(QueueableContext draft) {\n\t\tlog(DRAFT + '.f');\n\t}")))

    def test_a_loop_variable_read_as_the_constant_fails(self):
        self.assertEqual(1, len(problems("\tvoid f(List<String> all) {\n\t\tfor (String draft : all) { g(DRAFT); }\n\t}")))

    def test_the_initializer_still_reads_the_constant(self):
        self.assertEqual([], problems("\tvoid f() {\n\t\tString draft = 'x' + DRAFT;\n\t\tg(draft);\n\t}"))

    def test_a_local_outside_the_constants_use_passes(self):
        self.assertEqual([], problems("\tvoid f() {\n\t\t{ String draft = 'x'; g(draft); }\n\t\tg(DRAFT);\n\t}"))

    def test_an_allowlisted_name_passes(self):
        source = "public class Foo {\n\tstatic final String DRAFT = 'D';\n\tvoid f(Object draft) { g(DRAFT); }\n}"
        self.assertEqual([], check.problems_in_source(PATH, source, {"foo.draft"}))


if __name__ == "__main__":
    unittest.main()
