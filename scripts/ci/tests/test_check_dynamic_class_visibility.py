import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import apex_visibility as av  # noqa: E402

spec = importlib.util.spec_from_file_location("cdcv", os.path.join(HERE, "..", "check-dynamic-class-visibility.py"))
cdcv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cdcv)

DEPS = {"core": set(), "giving": {"core"}}
RESOLVER = """
public with sharing class Extensions {
    // 'Commented' is not a lookup
    private static final List<String> NAMES = new List<String>{ 'GoodExtension', 'BareExtension' };
    public static Object build(String name) {
        return NamespaceUtil.resolveType(name).newInstance();
    }
}
"""
GOOD = """
@NamespaceAccessible
public with sharing class GoodExtension {
    @NamespaceAccessible
    public GoodExtension() {
        return;
    }
}
"""
BARE = "@NamespaceAccessible\npublic with sharing class BareExtension {\n    public void run() {}\n}\n"
HANDLER = "public with sharing class GiftHandler extends TriggerHandler {\n    public GiftHandler() {}\n}\n"
CORE_HANDLER = "public with sharing class AccountHandler extends TriggerHandler {\n}\n"
COMMENTED = "public with sharing class Commented {\n}\n"


def build(extra=None):
    sources = {
        "packages/core/main/default/classes/Extensions.cls": RESOLVER,
        "packages/core/main/default/classes/AccountHandler.cls": CORE_HANDLER,
        "packages/giving/main/default/classes/GoodExtension.cls": GOOD,
        "packages/giving/main/default/classes/BareExtension.cls": BARE,
        "packages/giving/main/default/classes/GiftHandler.cls": HANDLER,
        "packages/giving/main/default/classes/Commented.cls": COMMENTED,
    }
    sources.update(extra or {})
    return av.Index(sources, DEPS)


def flagged(index, handlers=()):
    return sorted(message.split(" ")[0] for _, message in cdcv.problems(index, list(handlers)))


class DynamicClassVisibility(unittest.TestCase):
    def test_resolver_literals_need_an_annotated_constructor(self):
        self.assertEqual(flagged(build()), ["BareExtension"])

    def test_registry_handler_needs_class_and_constructor_annotation(self):
        found = cdcv.problems(build(), [("x.md-meta.xml", "GiftHandler")])
        names = [m for _, m in found if m.startswith("GiftHandler")]
        self.assertEqual(len(names), 1)
        self.assertIn("class is not @NamespaceAccessible", names[0])
        self.assertIn("no-argument constructor", names[0])

    def test_same_package_and_unknown_names_pass(self):
        self.assertEqual(flagged(build(), [("x", "AccountHandler"), ("y", "NoSuchClass")]), ["BareExtension"])

    def test_comment_apostrophe_does_not_hide_literals(self):
        resolver = RESOLVER.replace("// 'Commented' is not a lookup", "// a module's class")
        index = build({"packages/core/main/default/classes/Extensions.cls": resolver})
        self.assertEqual(flagged(index), ["BareExtension"])

    def test_argument_constructor_does_not_count(self):
        bare = BARE.replace("    public void run() {}", "    @NamespaceAccessible\n    public BareExtension(String x) {}")
        index = build({"packages/giving/main/default/classes/BareExtension.cls": bare})
        self.assertEqual(flagged(index), ["BareExtension"])

    def test_test_classes_are_not_resolvers(self):
        test_resolver = "@IsTest\nprivate class ExtensionsTest {\n    static void t() { Type.forName('BareExtension'); }\n}\n"
        index = build(
            {
                "packages/core/main/default/classes/Extensions.cls": "public with sharing class Extensions {\n}\n",
                "packages/core/main/default/classes/ExtensionsTest.cls": test_resolver,
            }
        )
        self.assertEqual(flagged(index), [])


if __name__ == "__main__":
    unittest.main()
