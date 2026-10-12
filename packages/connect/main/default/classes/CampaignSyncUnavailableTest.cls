/**
 * Campaign sync on an org without Campaign, the Platform-only shape no test org has
 * (ADR-0013, dynamic-apex.md section 9). `CampaignSyncService.unavailableForTest` makes the org
 * look that way, so the absent path is run and asserted here rather than skipped by the tests
 * that need Campaign: an appeal saves, nothing is linked, nothing is logged, and the page says
 * Campaign sync is unavailable.
 */
@IsTest
private class CampaignSyncUnavailableTest {
    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
            settings.Campaign_Sync_Enabled__c = true;
            upsert settings;
        }
    }

    private static User maria() {
        User maria = TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Campaign_Sync' }
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = maria.Id, UserPermissionsMarketingUser = true);
        }
        return maria;
    }

    private static Integer countLinked() {
        return [SELECT COUNT() FROM Appeal__c WHERE Campaign_Id__c != NULL WITH SYSTEM_MODE];
    }

    private static Integer countLogged() {
        Test.getEventBus().deliver();
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c = 'Campaign sync'
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void theSeamHidesCampaign() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CampaignSyncService.unavailableForTest = true;

            Assert.isNull(CampaignSyncService.campaignType(), 'No Campaign object.');
            Assert.isFalse(CampaignSyncService.isAvailable(), 'So the sync is unavailable.');
            Assert.isFalse(CampaignSyncService.canSync(), 'And nobody can sync.');
        }
    }

    @IsTest
    static void savingAppealsLinksNothingAndLogsNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CampaignSyncService.unavailableForTest = true;
            List<Appeal__c> appeals = new List<Appeal__c>();
            for (Integer i = 0; i < 200; i++) {
                appeals.add(new Appeal__c(Name = 'Appeal ' + i, Active__c = true));
            }

            Test.startTest();
            System.runAs(maria()) {
                insert appeals;
                update new Appeal__c(Id = appeals[0].Id, Goal__c = 1000);
            }
            Test.stopTest();

            Assert.areEqual(200, [SELECT COUNT() FROM Appeal__c], 'Every appeal saves.');
            Assert.areEqual(0, countLinked(), 'None is given a Campaign.');
            Assert.areEqual(0, countLogged(), 'An org without Campaign is not an error.');
        }
    }

    @IsTest
    static void syncAllAppealsDoesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new List<Appeal__c>{
                new Appeal__c(Name = 'Spring appeal', Active__c = true),
                new Appeal__c(Name = 'Gala', Active__c = true)
            };
            CampaignSyncService.unavailableForTest = true;

            Test.startTest();
            CampaignSyncService.Result result = CampaignSyncService.syncSaved(
                [SELECT Id, Name, Campaign_Id__c FROM Appeal__c WITH SYSTEM_MODE]
            );
            Test.stopTest();

            Assert.areEqual(0, result.created, 'No Campaign is made.');
            Assert.areEqual(0, result.updated, 'None is updated.');
            Assert.areEqual(0, countLinked(), 'No appeal is linked.');
        }
    }

    @IsTest
    static void thePageSaysUnavailableAndRefusesSyncAll() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CampaignSyncService.unavailableForTest = true;
            CampaignSyncController.Status status;
            String refusal;

            Test.startTest();
            System.runAs(maria()) {
                status = CampaignSyncController.getStatus();
                try {
                    CampaignSyncController.syncAll();
                } catch (AuraHandledException refused) {
                    refusal = refused.getMessage();
                }
            }
            Test.stopTest();

            Assert.isFalse(status.available, 'The page says Campaign sync cannot work here.');
            Assert.areEqual(
                Label.Connect_CampaignSync_Unavailable,
                refusal,
                'Sync all appeals is refused in words, before anything starts.'
            );
        }
    }
}
