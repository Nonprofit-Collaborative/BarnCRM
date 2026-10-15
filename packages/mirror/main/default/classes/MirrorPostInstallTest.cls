/**
 * Installing Mirror creates the Automation page's switches for Campaign sync and the Opportunity
 * mirror, switched on, and an upgrade leaves an administrator's choice alone (ADR-0056).
 */
@IsTest(testFor='ApexClass:MirrorPostInstall')
private class MirrorPostInstallTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static List<Automation_Setting__c> campaignSyncSwitch() {
        return [
            SELECT Id, Enabled__c
            FROM Automation_Setting__c
            WHERE Automation_Name__c = :CampaignSyncService.AUTOMATION_NAME
        ];
    }

    @IsTest
    static void installingMirrorCreatesTheCampaignSyncSwitch() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Test.testInstall(new MirrorPostInstall(), null);
            Test.stopTest();

            List<Automation_Setting__c> switches = campaignSyncSwitch();
            Assert.areEqual(1, switches.size(), 'The switch row exists from install.');
            Assert.isTrue(
                switches[0].Enabled__c,
                'It arrives on; the Giving setting is what is off.'
            );
        }
    }

    @IsTest
    static void upgradingKeepsTheAdministratorsChoice() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.testInstall(new MirrorPostInstall(), null);
            Automation_Setting__c row = campaignSyncSwitch()[0];
            row.Enabled__c = false;
            update row;

            Test.startTest();
            Test.testInstall(new MirrorPostInstall(), new Version(1, 0), true);
            Test.stopTest();

            List<Automation_Setting__c> switches = campaignSyncSwitch();
            Assert.areEqual(1, switches.size(), 'An upgrade does not add a second row.');
            Assert.isFalse(
                switches[0].Enabled__c,
                'The switch stays where the administrator left it.'
            );
        }
    }

    @IsTest
    static void installingMirrorCreatesTheOpportunityMirrorSwitch() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Test.testInstall(new MirrorPostInstall(), null);
            Test.stopTest();

            List<Automation_Setting__c> switches = [
                SELECT Enabled__c
                FROM Automation_Setting__c
                WHERE Automation_Name__c = :OpportunityMirrorService.AUTOMATION_NAME
            ];
            Assert.areEqual(1, switches.size(), 'The switch row exists from install.');
            Assert.isTrue(switches[0].Enabled__c, 'It arrives on; the direction setting is Off.');
        }
    }
}
