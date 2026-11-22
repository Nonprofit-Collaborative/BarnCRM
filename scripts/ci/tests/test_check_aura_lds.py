import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cal", os.path.join(HERE, "..", "check-aura-lds.py"))
cal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cal)


def apex(body, extra=""):
    return (
        "public with sharing class A {\n @AuraEnabled\n public static String m() {\n"
        + body
        + "\n }\n"
        + extra
        + "}"
    )


class AuraLds(unittest.TestCase):
    def test_flags_single_user_mode_query(self):
        src = apex("List<Task__c> t = [SELECT Id FROM Task__c WITH USER_MODE LIMIT 5]; return null;")
        self.assertEqual(cal.lds_candidates(src), {"m": "read"})

    def test_flags_single_record_dml(self):
        src = apex("update as user new Task__c(Id = x, Status__c = 'Done'); return null;")
        self.assertEqual(cal.lds_candidates(src), {"m": "write"})

    def test_ignores_aggregate_describe_and_system_mode(self):
        for body in (
            "return [SELECT COUNT() FROM Task__c WITH USER_MODE];",
            "Schema.getGlobalDescribe(); return [SELECT Id FROM Task__c WITH USER_MODE];",
            "return [SELECT Id FROM Task__c WITH SYSTEM_MODE];",
        ):
            self.assertEqual(cal.lds_candidates(apex(body)), {}, body)

    def test_ignores_service_call_and_two_queries(self):
        self.assertEqual(
            cal.lds_candidates(apex("TaskService.run(); update as user t; return null;")), {}
        )
        two = "a = [SELECT Id FROM A__c WITH USER_MODE]; b = [SELECT Id FROM B__c WITH USER_MODE];"
        self.assertEqual(cal.lds_candidates(apex(two)), {})

    def test_ignores_test_classes_and_comments(self):
        src = "@IsTest\n" + apex("update as user t;")
        self.assertEqual(cal.lds_candidates(src), {})
        self.assertEqual(cal.lds_candidates(apex("// update as user t;\n return null;")), {})

    def test_ignores_dml_words_in_string_literals(self):
        body = "try { return F.t(o); } catch (Exception e) { throw w(e, 'Bulk update fields'); }"
        self.assertEqual(cal.lds_candidates(apex(body)), {})

    def test_follows_same_class_helper(self):
        helper = "\n private static String h() { update as user t; TaskService.run(); return null; }\n"
        src = apex("update as user t; return h();", helper)
        self.assertEqual(cal.lds_candidates(src), {})

    def test_evaluate_reports_new_and_stale(self):
        new, stale = cal.evaluate({"A.m": "read", "B.n": "write"}, {"A.m", "C.o"})
        self.assertEqual(new, ["B.n"])
        self.assertEqual(stale, ["C.o"])


if __name__ == "__main__":
    unittest.main()
