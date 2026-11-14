import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
spec = importlib.util.spec_from_file_location("cas", os.path.join(HERE, "..", "check-api-surface.py"))
cas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cas)
from apex_source import strip  # noqa: E402

SOURCE = """
/** A class. */
@NamespaceAccessible
public with sharing class Thing extends Base implements Other {
	@NamespaceAccessible
	public static final String KEY = 'x';
	@NamespaceAccessible
	public static Map<String, Object> run(final Id recordId, List<String> names) {
		return null;
	}
	public static void notShared() {}
	global static Integer count(String value) { return 1; }
	// @NamespaceAccessible public static void commented() {}
}
"""


class ApiSurfaceTest(unittest.TestCase):
    def test_signatures_drop_names_annotations_and_bodies(self):
        self.assertEqual(
            cas.signatures(strip(SOURCE)),
            [
                "public class Thing",
                "public static final String KEY",
                "public static Map<String,Object> run(Id,List<String>)",
                "global static Integer count(String)",
            ],
        )

    def test_removed_or_changed_lines_and_new_ones_are_reported(self):
        removed, added = cas.diff(["a | x()", "a | y()", "a | y()"], ["a | y()", "a | z(String)"])
        self.assertEqual(removed, ["a | x()", "a | y()"])
        self.assertEqual(added, ["a | z(String)"])


if __name__ == "__main__":
    unittest.main()
