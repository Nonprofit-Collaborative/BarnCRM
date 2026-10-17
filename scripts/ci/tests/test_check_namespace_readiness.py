import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cnr", os.path.join(HERE, "..", "check-namespace-readiness.py"))
cnr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cnr)

DEPS = {"core": set(), "rollups": {"core"}, "giving": {"core"}}
CORE = "packages/core/main/default"
ROLLUPS = "packages/rollups/main/default"


def meta(exposed, *targets):
    body = "".join(f"<target>{t}</target>" for t in targets)
    return (
        '<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">'
        f"<isExposed>{str(exposed).lower()}</isExposed><targets>{body}</targets></LightningComponentBundle>"
    )


BASE = {
    f"{CORE}/lwc/shared/shared.js-meta.xml": meta(True, "lightning__RecordPage"),
    f"{CORE}/lwc/innerOnly/innerOnly.js-meta.xml": meta(False),
    f"{ROLLUPS}/lwc/own/own.js-meta.xml": meta(False),
    "packages/giving/main/default/lwc/gift/gift.js-meta.xml": meta(True),
    f"{CORE}/labels/CustomLabels.labels-meta.xml": (
        "<CustomLabels><labels><fullName>Open</fullName><protected>false</protected></labels>"
        "<labels><fullName>Closed</fullName><protected>true</protected></labels>"
        "<labels><fullName>Unsaid</fullName></labels></CustomLabels>"
    ),
}


def problems(extra):
    sources = dict(BASE)
    sources.update(extra)
    return sorted(m for (_, _, m) in cnr.check(sources, DEPS))


class NamespaceReadiness(unittest.TestCase):
    def test_lwc_import_and_tag_need_an_exposed_dependency_component(self):
        js = "import { a } from 'c/innerOnly';\nimport b from 'c/shared';\nimport c from 'c/own';\nimport g from 'c/gift';\n"
        html = "<template><c-inner-only></c-inner-only><c-shared></c-shared></template>"
        found = problems({f"{ROLLUPS}/lwc/x/x.js": js, f"{ROLLUPS}/lwc/x/x.html": html})
        self.assertEqual(
            found,
            [
                "component gift is in giving, which rollups does not depend on",
                "component innerOnly is core's and not isExposed",
                "component innerOnly is core's and not isExposed",
            ],
        )

    def test_flexipage_needs_the_page_target(self):
        page = (
            '<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">'
            "<componentName>shared</componentName><componentName>c:innerOnly</componentName>"
            "<componentName>flexipage:column</componentName><type>AppPage</type></FlexiPage>"
        )
        found = problems({f"{ROLLUPS}/flexipages/P.flexipage-meta.xml": page})
        self.assertEqual(
            found,
            ["component innerOnly is core's and not isExposed", "component shared has no lightning__AppPage target"],
        )

    def test_jest_tests_are_skipped(self):
        self.assertEqual(problems({f"{ROLLUPS}/lwc/x/__tests__/x.test.js": "import a from 'c/innerOnly';"}), [])

    def test_cross_package_labels_must_be_unprotected(self):
        apex = "public class X {\n String a = Label.Open; String b = System.Label.Closed; String c = Label.Unsaid;\n}"
        js = "import L from '@salesforce/label/c.Closed';"
        flow = "<Flow><errorMessage>{!$Label.Closed}</errorMessage></Flow>"
        found = problems(
            {
                f"{ROLLUPS}/classes/X.cls": apex,
                f"{ROLLUPS}/lwc/x/x.js": js,
                f"{ROLLUPS}/flows/F.flow-meta.xml": flow,
                f"{CORE}/classes/Own.cls": "public class Own { String a = Label.Closed; }",
            }
        )
        self.assertEqual(found, ["label Closed is core's and protected"] * 3 + ["label Unsaid is core's and protected"])

    def test_literal_state_keys_fail_outside_comments_and_tests(self):
        js = (
            "// state: { c__section: 'x' }\n/* 'c__id' */\nconst a = { c__section: 'x' };\n"
            "const b = { ['c__id']: 1 };\nconst ok = key.endsWith('__section');\n"
        )
        found = problems({f"{ROLLUPS}/lwc/x/x.js": js, f"{ROLLUPS}/lwc/x/__tests__/x.test.js": "s = { c__a: 1 };"})
        self.assertEqual(found, ["literal c__ page state key"] * 2)

    def test_strip_js_keeps_strings_and_lines(self):
        src = "a = 'http://x'; // c__gone\nb = `/* kept */`;\n"
        out = cnr.strip_js(src)
        self.assertIn("'http://x'", out)
        self.assertIn("`/* kept */`", out)
        self.assertNotIn("c__gone", out)
        self.assertEqual(out.count("\n"), src.count("\n"))


if __name__ == "__main__":
    unittest.main()
