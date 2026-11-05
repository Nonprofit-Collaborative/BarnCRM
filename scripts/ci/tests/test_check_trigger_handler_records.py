import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cthr", os.path.join(HERE, "..", "check-trigger-handler-records.py"))
cthr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cthr)


class TriggerHandlerRecords(unittest.TestCase):
    def test_flags_a_direct_read_in_a_handler(self):
        sources = {
            "classes/BadHandler.cls": "public class BadHandler extends TriggerHandler {\n"
            "  public override void afterInsert() { List<Contact> c = Trigger.new; }\n}"
        }
        self.assertEqual(len(cthr.check_sources(sources)), 1)

    def test_flags_each_companion_and_a_handler_of_a_handler(self):
        sources = {
            "classes/Base.cls": "public virtual class Base extends TriggerHandler {}",
            "classes/Child.cls": "public class Child extends Base {\n"
            "  void m() { Object a = Trigger.oldMap; Object b = Trigger.newMap; Object c = Trigger.old; }\n}",
        }
        self.assertEqual(len(cthr.check_sources(sources)), 3)

    def test_allows_the_accessors_other_trigger_properties_and_the_base_class(self):
        sources = {
            "classes/Fine.cls": "public class Fine extends TriggerHandler {\n"
            "  void m() { Object a = newRecords(); Boolean b = Trigger.isExecuting; }\n}",
            "classes/TriggerHandler.cls": "public virtual class TriggerHandler {\n"
            "  Object read() { return Trigger.new; }\n}",
        }
        self.assertEqual(cthr.check_sources(sources), [])

    def test_ignores_classes_that_are_not_handlers(self):
        sources = {"classes/Other.cls": "public class Other {\n  Object r() { return Trigger.new; }\n}"}
        self.assertEqual(cthr.check_sources(sources), [])


if __name__ == "__main__":
    unittest.main()
