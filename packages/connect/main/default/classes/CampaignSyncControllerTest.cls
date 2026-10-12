/**
 * The Campaign sync page (X-02, R-CS6): what it tells Maria, and the refusals Sync all appeals
 * gives before anything starts.
 */
@IsTest
private class CampaignSyncControllerTest {
    private static void switchOn(Boolean enabled) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Campaign_Sync_Enabled__c = enabled;
        upsert settings;
    }

    /** Maria: BarnCRM Admin, Campaign access, Marketing User and the Campaign Sync set. */
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

    private static CampaignSyncController.Status ready() {
        CampaignSyncController.Status status = new CampaignSyncController.Status();
        status.available = true;
        status.switchedOn = true;
        status.canSync = true;
        status.canManage = true;
        status.running = false;
        return status;
    }

    @IsTest
    static void theStatusCountsTheAppealsWithACampaign() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            switchOn(false);
            insert new List<Appeal__c>{
                new Appeal__c(Name = 'Spring appeal', Active__c = true),
                new Appeal__c(Name = 'Gala', Active__c = true)
            };
            CampaignSyncController.Status status;
            Test.startTest();
            System.runAs(maria()) {
                status = CampaignSyncController.getStatus();
            }
            Test.stopTest();
            Assert.areEqual(
                CampaignSyncService.isAvailable(),
                status.available,
                'Read from the org.'
            );
            Assert.isFalse(status.switchedOn, 'Off at install.');
            Assert.areEqual(2, status.appealCount, 'Both appeals are counted.');
            Assert.areEqual(0, status.linkedCount, 'Neither has a Campaign while the sync is off.');
            Assert.isFalse(status.running, 'Nothing is running.');
            Assert.isFalse(status.appealCountCapped, 'Two appeals is an exact count.');
        }
    }

    @IsTest
    static void pastTheCapTheCountStopsAndSaysSo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            switchOn(false);
            insert new List<Appeal__c>{
                new Appeal__c(Name = 'Spring appeal', Active__c = true),
                new Appeal__c(Name = 'Gala', Active__c = true),
                new Appeal__c(Name = 'Year end', Active__c = true)
            };
            CampaignSyncController.countCap = 2;
            CampaignSyncController.Status status;
            Test.startTest();
            System.runAs(maria()) {
                status = CampaignSyncController.getStatus();
            }
            Test.stopTest();
            Assert.areEqual(2, status.appealCount, 'The count stops at the cap.');
            Assert.isTrue(status.appealCountCapped, 'and says there are more.');
            Assert.isFalse(status.linkedCountCapped, 'None linked is still exact.');
        }
    }

    @IsTest
    static void syncAllStartsTheRunForMaria() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!CampaignSyncService.isAvailable()) {
                return;
            }
            switchOn(false);
            insert new Appeal__c(Name = 'Spring appeal', Active__c = true);
            switchOn(true);
            CampaignSyncBatch.chainSecondPass = false;
            CampaignSyncController.Status status;
            Test.startTest();
            System.runAs(maria()) {
                status = CampaignSyncController.syncAll();
            }
            Test.stopTest();
            Assert.isTrue(status.running, 'The page is told the run has started.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Appeal__c WHERE Campaign_Id__c != NULL WITH SYSTEM_MODE],
                'The run gave the appeal its Campaign.'
            );
        }
    }

    @IsTest
    static void syncAllIsRefusedInWordsWhileTheSyncIsOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            switchOn(false);
            String message;
            Test.startTest();
            System.runAs(maria()) {
                try {
                    CampaignSyncController.syncAll();
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
            }
            Test.stopTest();
            Assert.areEqual(
                CampaignSyncService.isAvailable()
                    ? Label.Connect_CampaignSync_SwitchedOff
                    : Label.Connect_CampaignSync_Unavailable,
                message,
                'Nothing starts, and the page says why.'
            );
        }
    }

    @IsTest
    static void eachRefusalNamesItsOwnReason() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CampaignSyncController.Status status = ready();
            Assert.isNull(CampaignSyncController.refusal(status), 'Everything allows it.');
            status.running = true;
            Assert.areEqual(
                Label.Connect_CampaignSync_Running,
                CampaignSyncController.refusal(status)
            );
            status.canSync = false;
            Assert.areEqual(
                Label.Connect_CampaignSync_NoCampaignAccess,
                CampaignSyncController.refusal(status)
            );
            status.canManage = false;
            Assert.areEqual(
                Label.Connect_CampaignSync_NoManagePermission,
                CampaignSyncController.refusal(status)
            );
            status.switchedOn = false;
            Assert.areEqual(
                Label.Connect_CampaignSync_SwitchedOff,
                CampaignSyncController.refusal(status)
            );
            status.available = false;
            Assert.areEqual(
                Label.Connect_CampaignSync_Unavailable,
                CampaignSyncController.refusal(status)
            );
        }
    }
}
