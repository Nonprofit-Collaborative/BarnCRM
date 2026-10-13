/**
 * Connect's Health Check finding (X-01, R-OM8): a scheduled Opportunity mirror run that has not
 * completed for more than two days is reported to Maria, in Core's one report, and only when the
 * mirror is scheduled, on, and she may manage settings.
 */
@IsTest(testFor='ApexClass:ConnectHealthCheckExtension')
private class ConnectHealthCheckExtensionTest {
    private static void choose(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Boolean reported(List<HealthCheckService.Finding> findings) {
        for (HealthCheckService.Finding finding : findings) {
            if (finding.key == ConnectHealthCheckExtension.MIRROR_STALE_KEY) {
                return true;
            }
        }
        return false;
    }

    /**
     * The absent branch of every test that stops where the org has no Opportunity: a run
     * scheduled and three days late is not reported, since no run can work there (R-OM1).
     * `OpportunityMirrorUnavailableTest` runs this branch.
     */
    private static void assertNothingReported() {
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        System.runAs(maria()) {
            OpportunityMirrorSchedulable.schedule();
            ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
            Assert.isFalse(
                reported(new ConnectHealthCheckExtension().findings()),
                'Without Opportunity there is no run to be late.'
            );
        }
    }

    @IsTest
    static void aScheduledRunThatHasNotRunForTwoDaysIsReportedInCoresReport() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingReported();
                return;
            }
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            User admin = maria();
            Test.startTest();
            System.runAs(admin) {
                OpportunityMirrorSchedulable.schedule();
                Assert.isFalse(
                    reported(new ConnectHealthCheckExtension().findings()),
                    'Just scheduled: nothing to say yet.'
                );
                ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
                Assert.isTrue(reported(HealthCheckService.run()), 'Core finds Connect by name.');
                ConnectSettingsWriter.recordOpportunityMirrorRun(System.now().addDays(2), 'Ran');
                Assert.isFalse(
                    reported(new ConnectHealthCheckExtension().findings()),
                    'A run completed a day ago.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void nothingIsReportedWhenTheRunIsNotExpected() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!OpportunityMirrorService.isAvailable()) {
                assertNothingReported();
                return;
            }
            ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
            User admin = maria();
            User viewer = TestDataFactory.createUserOnTheRunningUsersProfile(
                'Ana',
                new List<String>{ 'Giving_Admin' }
            );
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            Test.startTest();
            System.runAs(admin) {
                Assert.isFalse(
                    reported(new ConnectHealthCheckExtension().findings()),
                    'Not scheduled.'
                );
                OpportunityMirrorSchedulable.schedule();
            }
            System.runAs(viewer) {
                Assert.isFalse(
                    reported(new ConnectHealthCheckExtension().findings()),
                    'Only a viewer who may manage settings is told.'
                );
            }
            choose(OpportunityMirrorService.OFF);
            System.runAs(admin) {
                Assert.isFalse(reported(new ConnectHealthCheckExtension().findings()), 'Off.');
            }
            Test.stopTest();
        }
    }
}
