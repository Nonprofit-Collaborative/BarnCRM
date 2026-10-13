/**
 * OrgOptimizerSetupController: the Unused setup section runs every check, finds a permission
 * set nobody is assigned, reports a check that cannot run as failed without hiding the others,
 * and refuses a person without Manage BarnCRM Settings.
 */
@IsTest
private class OrgOptimizerSetupControllerTest {
    private static final List<String> KEYS = new List<String>{
        'inactiveUsers',
        'unassignedPermissionSets',
        'staleReports',
        'unusedEmailTemplates',
        'inactiveFlows',
        'jobsOfInactiveUsers'
    };

    private static Map<String, OrgOptimizerSetupController.Finding> byKey(
        OrgOptimizerSetupController.Result result
    ) {
        Map<String, OrgOptimizerSetupController.Finding> findings = new Map<String, OrgOptimizerSetupController.Finding>();
        for (OrgOptimizerSetupController.Finding finding : result.findings) {
            findings.put(finding.key, finding);
        }
        return findings;
    }

    @IsTest
    static void findsAPermissionSetNobodyIsAssigned() {
        String name = 'Unused_Setup_Test_Set';
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSet(Name = name, Label = 'Aaa Unused Setup Test Set');
        }
        System.runAs(TestUsers.admin()) {
            OrgOptimizerSetupController.permissionOverride = true;

            Test.startTest();
            OrgOptimizerSetupController.Result result = OrgOptimizerSetupController.getFindings();
            Test.stopTest();

            Map<String, OrgOptimizerSetupController.Finding> findings = byKey(result);
            Assert.areEqual(KEYS.size(), result.findings.size(), 'One finding per check.');
            for (String key : KEYS) {
                OrgOptimizerSetupController.Finding finding = findings.get(key);
                Assert.isNotNull(finding, 'Every check is reported: ' + key);
                Assert.isTrue(finding.setupUrl.startsWith('/lightning/'), 'With its Setup page.');
                Assert.isTrue(
                    finding.failed || finding.count >= 0,
                    'Either a count or "could not check": ' + key
                );
                Assert.isTrue(finding.examples.size() <= 5, 'At most five examples.');
            }
            OrgOptimizerSetupController.Finding sets = findings.get('unassignedPermissionSets');
            Assert.isFalse(sets.failed, 'Permission sets are readable by an administrator.');
            Assert.isTrue(sets.count >= 1, 'The new permission set has nobody assigned.');
            Assert.isTrue(
                sets.examples.contains('Aaa Unused Setup Test Set') || sets.count > 5,
                'It is named among the examples, which are in label order.'
            );
            Assert.isFalse(findings.get('inactiveUsers').failed, 'Users are always readable.');
        }
    }

    @IsTest
    static void aCheckThatCannotRunDoesNotHideTheOthers() {
        System.runAs(TestUsers.admin()) {
            OrgOptimizerSetupController.permissionOverride = true;
            OrgOptimizerSetupController.failCheck = 'staleReports';

            Map<String, OrgOptimizerSetupController.Finding> findings = byKey(
                OrgOptimizerSetupController.getFindings()
            );

            OrgOptimizerSetupController.Finding reports = findings.get('staleReports');
            Assert.isTrue(reports.failed, 'The broken check says so.');
            Assert.isNull(reports.count, 'With no count.');
            Assert.isFalse(findings.get('inactiveUsers').failed, 'The others still run.');
        }
    }

    @IsTest
    static void refusesAPersonWhoCannotManageSettings() {
        System.runAs(TestUsers.admin()) {
            OrgOptimizerSetupController.permissionOverride = false;
            try {
                OrgOptimizerSetupController.getFindings();
                Assert.fail('A person without the permission is refused.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Core_OrgOptimizer_ErrorNoPermission,
                    refused.getMessage(),
                    'With the sentence that says which permission.'
                );
            }
        }
    }
}
