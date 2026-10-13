/**
 * The last full Health Check result that BarnCRM Home shows instead of running every check on
 * each load (ADMIN-7).
 */
@IsTest
private class HealthCheckLastRunTest {
    private static HealthCheckService.Finding finding(String key, String severity) {
        return new HealthCheckService.Finding(
            key,
            key,
            key,
            severity,
            HealthCheckService.CATEGORY_SETTINGS
        );
    }

    private static HealthCheckService.Report reportWithOneOfEach(Boolean canManage) {
        HealthCheckService.Report report = new HealthCheckService.Report();
        report.canManageSettings = canManage;
        report.findings.add(finding('a', HealthCheckService.SEVERITY_ERROR));
        report.findings.add(finding('b', HealthCheckService.SEVERITY_WARNING));
        report.findings.add(finding('c', HealthCheckService.SEVERITY_WARNING));
        report.findings.add(finding('d', HealthCheckService.SEVERITY_INFO));
        return report;
    }

    @IsTest
    static void anAdministratorsRunIsKeptAndReadBack() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            HealthCheckLastRun.Summary before = HealthCheckLastRun.read();
            HealthCheckLastRun.record(reportWithOneOfEach(true));
            HealthCheckLastRun.Summary after = HealthCheckLastRun.read();
            Test.stopTest();

            Assert.isNull(before.ranAt, 'Nothing is kept before the first run');
            Assert.isNull(before.result, 'so there is no result to show');
            Assert.isNotNull(after.ranAt, 'The run time is kept');
            Assert.areEqual(1, after.errors, 'One to fix');
            Assert.areEqual(2, after.warnings, 'Two to be aware of');
            Assert.areEqual(1, after.infos, 'One for information');
            Assert.areEqual(
                String.format(
                    System.Label.Core_HealthCheck_LastResult,
                    new List<Object>{ 1, 2, 1 }
                ),
                after.result,
                'And read back as a sentence'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Setting_Change__c],
                'A run record is bookkeeping, not a settings change'
            );
        }
    }

    @IsTest
    static void aRunThatSkipsTheAccessChecksIsNotKept() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            HealthCheckLastRun.record(reportWithOneOfEach(false));
            HealthCheckLastRun.Summary after = HealthCheckLastRun.read();
            Test.stopTest();

            Assert.isNull(after.ranAt, 'A partial run would understate the result');
        }
    }

    @IsTest
    static void anUnreadableResultReadsAsNeverRun() {
        System.runAs(TestUsers.admin()) {
            OrgSettingsSystemWriter.save(
                new Map<Schema.SObjectField, Object>{
                    BarnCRM_Settings__c.Health_Check_Last_Run__c => Datetime.now(),
                    BarnCRM_Settings__c.Health_Check_Last_Result__c => 'one,two,three'
                }
            );

            Test.startTest();
            HealthCheckLastRun.Summary after = HealthCheckLastRun.read();
            Test.stopTest();

            Assert.isNull(after.ranAt, 'Shown as never run, so Run now puts it right');
            Assert.isNull(after.result, 'with no result');
        }
    }

    @IsTest
    static void aFullRunFromTheControllerIsWhatHomeShowsNext() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                HealthCheckController.getReport();
                Assert.isNull(
                    HealthCheckController.getLastRun().ranAt,
                    'A run by someone without the permission is not kept'
                );
            }

            System.runAs(maria) {
                Test.startTest();
                HealthCheckService.Report report = HealthCheckController.getReport();
                HealthCheckLastRun.Summary shown = HealthCheckController.getLastRun();
                Test.stopTest();

                Integer total = shown.errors + shown.warnings + shown.infos;
                Assert.isNotNull(shown.ranAt, 'Her full run is kept');
                Assert.areEqual(report.findings.size(), total, 'with every finding counted once');
            }
        }
    }
}
