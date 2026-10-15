import importlib.util
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import apex_visibility as av  # noqa: E402

spec = importlib.util.spec_from_file_location("ccpv", os.path.join(HERE, "..", "check-cross-package-visibility.py"))
ccpv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ccpv)

DEPS = {"core": set(), "rollups": {"core"}}

CORE = """
@NamespaceAccessible
public with sharing class Util {
    @NamespaceAccessible
    public static final String OK = 'a';
    public static final String HIDDEN = 'b';
    @NamespaceAccessible
    public static Shape detect() { return null; }
    public static void plain() {}
    @NamespaceAccessible
    public class Shape {
        @NamespaceAccessible
        public Boolean shared;
        public Boolean unshared;
    }
    public class Closed {
        @NamespaceAccessible
        public String x;
    }
    public class Built {
        private Built() {}
    }
}
"""
HIDDEN_CLASS = "public with sharing class Hidden {\n    public static void run() {}\n}\n"


def index(module_source, extra=None):
    sources = {
        "packages/core/main/default/classes/Util.cls": CORE,
        "packages/core/main/default/classes/Hidden.cls": HIDDEN_CLASS,
        "packages/rollups/main/default/classes/Mod.cls": module_source,
    }
    sources.update(extra or {})
    return av.Index(sources, DEPS)


def targets(module_source, extra=None):
    return sorted(target for (_, target) in ccpv.violations(index(module_source, extra)))


def module(body):
    return "public with sharing class Mod {\n    public void go() {\n" + body + "\n    }\n}\n"


class CrossPackageVisibility(unittest.TestCase):
    def test_annotated_members_pass(self):
        self.assertEqual(targets(module("String s = Util.OK; Util.Shape sh = Util.detect(); Boolean b = sh.shared;")), [])

    def test_flags_unannotated_class(self):
        self.assertEqual(targets(module("Hidden.run();")), ["Hidden", "Hidden.run"])

    def test_flags_unannotated_static_member(self):
        self.assertEqual(targets(module("String s = Util.HIDDEN; Util.plain();")), ["Util.HIDDEN", "Util.plain"])

    def test_flags_inner_type_and_its_fields(self):
        self.assertEqual(targets(module("Util.Closed c; String v = c.x;")), ["Util.Closed", "Util.Closed.x"])

    def test_flags_field_read_through_variable(self):
        self.assertEqual(targets(module("Util.Shape sh = null; Boolean b = sh.unshared;")), ["Util.Shape.unshared"])

    def test_flags_field_read_through_static_call(self):
        self.assertEqual(targets(module("Boolean b = Util.detect().unshared;")), ["Util.Shape.unshared"])

    def test_flags_private_constructor(self):
        self.assertIn("Util.Built()", targets(module("Object o = new Util.Built();")))

    def test_ignores_comments_strings_and_test_classes(self):
        self.assertEqual(targets(module("// Hidden.run();\n String s = 'Hidden.run()';")), [])
        test_class = "@IsTest\nprivate class ModTest {\n    static void t() { Hidden.run(); }\n}\n"
        found = targets(module(""), {"packages/rollups/main/default/classes/ModTest.cls": test_class})
        self.assertEqual(found, [])

    def test_own_inner_type_shadows_other_package(self):
        src = "public with sharing class Mod {\n    public class Hidden extends Exception {}\n    void go() { throw new Hidden(); }\n}\n"
        self.assertEqual(targets(src), [])

    def test_core_is_not_scanned_against_modules(self):
        mod = "public with sharing class Mod {\n    public static void run() {}\n}\n"
        core_user = "public with sharing class CoreUser {\n    void go() { Mod.run(); }\n}\n"
        found = targets(mod, {"packages/core/main/default/classes/CoreUser.cls": core_user})
        self.assertEqual(found, [])

    def test_allowlist_needs_a_reason(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "allowlist.txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write("# comment\nMod Util.HIDDEN: known\nMod Util.plain\n")
            entries, errors = av.read_allowlist(path)
        self.assertEqual(set(entries), {("Mod", "Util.HIDDEN")})
        self.assertEqual(len(errors), 1)


if __name__ == "__main__":
    unittest.main()
