import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cana", os.path.join(HERE, "..", "check-aura-namespace-accessible.py"))
cana = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cana)


class AuraNamespaceAccessible(unittest.TestCase):
    def test_flags_field_with_both(self):
        src = "public class A {\n @AuraEnabled\n @NamespaceAccessible\n public String name;\n}"
        self.assertEqual(len(cana.check_text(src)), 1)

    def test_flags_property_and_reverse_order(self):
        src = "public class A {\n @NamespaceAccessible @AuraEnabled public String n { get; set; }\n}"
        self.assertEqual(len(cana.check_text(src)), 1)

    def test_allows_class_and_single_annotations(self):
        src = (
            "@NamespaceAccessible\npublic class A {\n @AuraEnabled\n public String a;\n"
            " @NamespaceAccessible\n public String b;\n"
            " @NamespaceAccessible\n public static String m() { return null; }\n}"
        )
        self.assertEqual(cana.check_text(src), [])

    def test_flags_method_with_both(self):
        src = "public class A {\n @AuraEnabled(cacheable=true)\n @NamespaceAccessible\n public static String m() { return null; }\n}"
        self.assertEqual(len(cana.check_text(src)), 1)

    def test_ignores_comments(self):
        src = "public class A {\n // @AuraEnabled @NamespaceAccessible\n public String a;\n}"
        self.assertEqual(cana.check_text(src), [])


if __name__ == "__main__":
    unittest.main()
