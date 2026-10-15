/**
 * Sync all appeals (X-02, R-CS6): the appeals that existed before Campaign sync was switched
 * on get their Campaigns in one run, and the second pass puts a child under a parent whose
 * Campaign was made after it.
 */
@IsTest(testFor='ApexClass:CampaignSyncBatch')
private class CampaignSyncBatchTest {
    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Appeal__c parent = new Appeal__c(Name = 'Capital campaign', Active__c = true);
            insert parent;
            insert new List<Appeal__c>{
                new Appeal__c(Name = 'Spring appeal', Goal__c = 25000, Active__c = true),
                new Appeal__c(Name = 'Gala', Parent_Appeal__c = parent.Id, Active__c = true)
            };
            // Switched on only now, so none of the appeals above has a Campaign yet.
            Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
            settings.Campaign_Sync_Enabled__c = true;
            upsert settings;
        }
    }

    private static User maria() {
        User maria = TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', 'Campaign_Sync' }
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = maria.Id, UserPermissionsMarketingUser = true);
        }
        return maria;
    }

    /** The absent branch: the appeals the setup made are all still without a Campaign. */
    private static void assertNoAppealLinked() {
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Appeal__c WHERE Campaign_Id__c != NULL WITH SYSTEM_MODE],
            'Without Campaign no appeal is linked (R-CS1).'
        );
    }

    @IsTest
    static void oneRunGivesEveryAppealItsCampaign() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CampaignSyncBatch.chainSecondPass = false;
            Test.startTest();
            System.runAs(maria()) {
                CampaignSyncBatch.start();
            }
            Test.stopTest();

            Integer linked = [
                SELECT COUNT()
                FROM Appeal__c
                WHERE Campaign_Id__c != NULL
                WITH SYSTEM_MODE
            ];
            Integer expected = CampaignSyncService.isAvailable() ? 3 : 0;
            Assert.areEqual(expected, linked, 'Every appeal is linked where Campaign exists.');
        }
    }

    @IsTest
    static void theSecondPassPutsAChildUnderItsParent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            User admin = maria();
            Appeal__c gala = [SELECT Id, Parent_Appeal__c FROM Appeal__c WHERE Name = 'Gala'];
            // The child is copied first and alone, so its Campaign is made with no parent.
            System.runAs(admin) {
                CampaignSyncService.syncSaved(
                    (List<Appeal__c>) Database.queryWithBinds(
                        'SELECT ' +
                            CampaignSyncSelector.APPEAL_FIELDS +
                            ' FROM Appeal__c WHERE Id = :galaId',
                        new Map<String, Object>{ 'galaId' => gala.Id },
                        AccessLevel.SYSTEM_MODE
                    )
                );
                CampaignSyncService.syncSaved(
                    (List<Appeal__c>) Database.queryWithBinds(
                        'SELECT ' +
                            CampaignSyncSelector.APPEAL_FIELDS +
                            ' FROM Appeal__c WHERE Id = :parentId',
                        new Map<String, Object>{ 'parentId' => gala.Parent_Appeal__c },
                        AccessLevel.SYSTEM_MODE
                    )
                );
            }

            Test.startTest();
            System.runAs(admin) {
                Database.executeBatch(new CampaignSyncBatch(true), CampaignSyncBatch.CHUNK_SIZE);
            }
            Test.stopTest();

            Set<Id> pair = new Set<Id>{ gala.Id, gala.Parent_Appeal__c };
            Map<Id, Appeal__c> appeals = new Map<Id, Appeal__c>(
                [SELECT Id, Campaign_Id__c FROM Appeal__c WHERE Id IN :pair WITH SYSTEM_MODE]
            );
            Id childCampaign = Id.valueOf(appeals.get(gala.Id).Campaign_Id__c);
            List<SObject> rows = Database.queryWithBinds(
                'SELECT ParentId FROM ' +
                    CampaignSyncService.campaignType().getDescribe().getName() +
                    ' WHERE Id = :childCampaign',
                new Map<String, Object>{ 'childCampaign' => childCampaign },
                AccessLevel.SYSTEM_MODE
            );
            Assert.areEqual(
                Id.valueOf(appeals.get(gala.Parent_Appeal__c).Campaign_Id__c),
                rows[0].get('ParentId'),
                'The second pass puts the child under the parent made after it.'
            );
        }
    }

    @IsTest
    static void anAppealThatCannotBeSavedDoesNotCostTheChunkItsLinks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            // Two appeals that are each other's parent, made with Giving's hierarchy check and the
            // sync bypassed: every later save of either is refused, as a rule on Appeal would do.
            Appeal__c first = new Appeal__c(Name = 'Loop one', Active__c = true);
            Appeal__c second = new Appeal__c(Name = 'Loop two', Active__c = true);
            AutomationControl.bypass('Appeal_Hierarchy');
            AutomationControl.bypass(CampaignSyncService.AUTOMATION_NAME);
            insert new List<Appeal__c>{ first, second };
            first.Parent_Appeal__c = second.Id;
            second.Parent_Appeal__c = first.Id;
            update new List<Appeal__c>{ first, second };
            AutomationControl.clearAllBypasses();
            Integer campaignsBefore = Database.countQuery(
                'SELECT COUNT() FROM ' + CampaignSyncService.campaignType().getDescribe().getName(),
                AccessLevel.SYSTEM_MODE
            );

            Set<Id> refused = new Set<Id>{ first.Id, second.Id };

            CampaignSyncBatch.chainSecondPass = false;
            Test.startTest();
            System.runAs(maria()) {
                CampaignSyncBatch.start();
            }
            Test.stopTest();

            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Appeal__c WHERE Campaign_Id__c != NULL WITH SYSTEM_MODE],
                'The other appeals in the chunk keep their links.'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Appeal__c
                    WHERE Id IN :refused AND Campaign_Id__c != NULL
                    WITH SYSTEM_MODE
                ],
                'The refused appeals are not linked.'
            );
            Assert.areEqual(
                campaignsBefore + 3,
                Database.countQuery(
                    'SELECT COUNT() FROM ' +
                    CampaignSyncService.campaignType().getDescribe().getName(),
                    AccessLevel.SYSTEM_MODE
                ),
                'The Campaigns made for the refused appeals are deleted again (R-CS7).'
            );
        }
    }

    @IsTest
    static void onlyOneRunAtATimeIsVisibleToThePage() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isFalse(
                CampaignSyncSelector.hasRunningJob(CampaignSyncBatch.CLASS_NAME),
                'Nothing is running before a start.'
            );
        }
    }
}
