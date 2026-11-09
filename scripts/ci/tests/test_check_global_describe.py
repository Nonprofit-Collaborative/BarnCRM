import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "check_global_describe", os.path.join(HERE, "..", "check-global-describe.py")
)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)


class CheckGlobalDescribeTest(unittest.TestCase):
    def test_a_direct_call_fails(self):
        problems = check.check_sources(
            {"packages/x/main/default/classes/Foo.cls": "class Foo { void f() { Schema.getGlobalDescribe(); } }"}
        )
        self.assertEqual(1, len(problems))
        self.assertIn("Foo.cls:1", problems[0])

    def test_namespace_util_and_tests_pass(self):
        problems = check.check_sources(
            {
                "packages/core/main/default/classes/NamespaceUtil.cls": "class N { void f() { Schema.getGlobalDescribe(); } }",
                "packages/x/main/default/classes/FooTest.cls": "class FooTest { void f() { Schema.getGlobalDescribe(); } }",
                "packages/x/main/default/classes/Helper.cls": "@IsTest\nprivate class Helper { void f() { Schema.getGlobalDescribe(); } }",
                "packages/x/main/default/classes/Bar.cls": "class Bar { void f() { NamespaceUtil.globalDescribe(); } }",
            }
        )
        self.assertEqual([], problems)


if __name__ == "__main__":
    unittest.main()
