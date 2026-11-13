import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "check_async_starter", os.path.join(HERE, "..", "check-async-starter.py")
)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

FOO = "packages/x/main/default/classes/Foo.cls"


class CheckAsyncStarterTest(unittest.TestCase):
    def test_a_direct_call_outside_the_allowlist_fails(self):
        problems = check.check_sources({FOO: "class Foo { void f() { Database.executeBatch(b, 1); } }"}, {})
        self.assertEqual(1, len(problems))
        self.assertIn("AsyncStarter", problems[0])

    def test_an_allowance_is_a_ceiling_and_a_floor(self):
        source = "class Foo { void f() { System.enqueueJob(j); } }"
        self.assertEqual([], check.check_sources({FOO: source}, {FOO: 1}))
        self.assertEqual(1, len(check.check_sources({FOO: source}, {FOO: 2})))

    def test_the_starter_tests_and_starter_calls_pass(self):
        problems = check.check_sources(
            {
                "packages/core/main/default/classes/AsyncStarter.cls": "class A { void f() { System.enqueueJob(j); } }",
                "packages/x/main/default/classes/FooTest.cls": "class FooTest { void f() { System.enqueueJob(j); } }",
                FOO: "class Foo { void f() { AsyncStarter.queue(j, 'Foo'); } }",
            },
            {},
        )
        self.assertEqual([], problems)

    def test_a_listed_file_that_is_gone_fails(self):
        self.assertEqual(1, len(check.check_sources({}, {FOO: 1})))

    def test_the_allowlist_reads_paths_counts_and_comments(self):
        self.assertEqual({FOO: 2}, check.read_allowlist("# why\n" + FOO + " 2  # reason\n\n"))


if __name__ == "__main__":
    unittest.main()
