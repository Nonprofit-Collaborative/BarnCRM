/**
 * Campaign sync (X-02, canonical model Section 29B) as Maria and David see it: saving an
 * appeal gives it a Campaign, a change follows it there, and nothing about the Campaign ever
 * refuses the appeal.
 *
 * Campaign is read only through dynamic queries here too, so this class compiles where
 * Campaign does not exist; on such an org every test checks that the sync did nothing and
 * stops (R-CS1).
 */
@IsTest
private class CampaignSyncServiceTest {
    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            switchOn(true);
        }
    }

    private static void switchOn(Boolean enabled) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Campaign_Sync_Enabled__c = enabled;
        upsert settings;
    }

    /** Maria: an administrator who holds Campaign access and the Marketing User box. */
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

    /** Campaigns read back by the name describe gives, so the class compiles without one. */
    private static Map<Id, SObject> campaigns(Set<Id> ids) {
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    CampaignSyncSelector.CAMPAIGN_FIELDS +
                    ' FROM ' +
                    CampaignSyncService.campaignType().getDescribe().getName() +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    private static Integer countCampaigns() {
        return Database.countQuery(
            'SELECT COUNT() FROM ' + CampaignSyncService.campaignType().getDescribe().getName(),
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * The absent branch of every test that stops where the org has no Campaign: the appeals
     * saved, and none of them was given a Campaign.
     */
    private static void assertNoAppealLinked() {
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Appeal__c WHERE Campaign_Id__c != NULL WITH SYSTEM_MODE],
            'Without Campaign no appeal is linked (R-CS1).'
        );
    }

    private static Integer countWarnings() {
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c = 'Campaign sync' AND Severity__c = 'Warning'
            WITH SYSTEM_MODE
        ];
    }

    private static SObject campaign(String campaignId) {
        return campaigns(new Set<Id>{ Id.valueOf(campaignId) }).get(Id.valueOf(campaignId));
    }

    private static Appeal__c reread(Id appealId) {
        return (Appeal__c) Database.queryWithBinds(
            'SELECT ' + CampaignSyncSelector.APPEAL_FIELDS + ' FROM Appeal__c WHERE Id = :appealId',
            new Map<String, Object>{ 'appealId' => appealId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static Appeal__c springAppeal() {
        return new Appeal__c(
            Name = 'Spring appeal',
            Description__c = 'The spring letter to every donor.',
            Start_Date__c = Date.newInstance(2026, 3, 2),
            End_Date__c = Date.newInstance(2026, 5, 29),
            Goal__c = 25000,
            Cost__c = 1200,
            Active__c = true
        );
    }

    @IsTest
    static void savingAnAppealGivesItACampaignWithTheSameValues() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Appeal__c spring = springAppeal();
            Test.startTest();
            System.runAs(maria()) {
                insert spring;
            }
            Test.stopTest();

            Appeal__c saved = reread(spring.Id);
            if (!CampaignSyncService.isAvailable()) {
                Assert.isNull(saved.Campaign_Id__c, 'Without Campaign the sync does nothing.');
                return;
            }
            Assert.isNotNull(
                saved.Campaign_Id__c,
                'The Campaign is linked in the same save (R-CS3).'
            );
            SObject copy = campaign(saved.Campaign_Id__c);
            Assert.areEqual('Spring appeal', copy.get('Name'), 'Name is copied.');
            Assert.areEqual(
                saved.Description__c,
                copy.get('Description'),
                'Description is copied.'
            );
            Assert.areEqual(saved.Start_Date__c, copy.get('StartDate'), 'Start Date is copied.');
            Assert.areEqual(saved.End_Date__c, copy.get('EndDate'), 'End Date is copied.');
            Assert.areEqual(
                25000,
                (Decimal) copy.get('ExpectedRevenue'),
                'Goal is Expected Revenue.'
            );
            Assert.areEqual(1200, (Decimal) copy.get('ActualCost'), 'Cost is Actual Cost.');
            Assert.areEqual(true, copy.get('IsActive'), 'Active is copied.');
            Assert.isNull(copy.get('ParentId'), 'No parent appeal, no parent Campaign.');
        }
    }

    @IsTest
    static void aChangeToTheAppealFollowsItToTheCampaignAndNothingComesBack() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Appeal__c spring = springAppeal();
            System.runAs(admin) {
                insert spring;
            }
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            String link = reread(spring.Id).Campaign_Id__c;

            Test.startTest();
            System.runAs(admin) {
                update new Appeal__c(Id = spring.Id, Name = 'spring appeal', Goal__c = 30000);
                SObject handEdited = CampaignSyncService.campaignType()
                    .newSObject(Id.valueOf(link));
                handEdited.put('Description', 'Edited on the Campaign');
                update handEdited;
            }
            Test.stopTest();

            SObject copy = campaign(link);
            Assert.areEqual(
                'spring appeal',
                copy.get('Name'),
                'A change of case alone is still a change.'
            );
            Assert.areEqual(
                30000,
                (Decimal) copy.get('ExpectedRevenue'),
                'The new goal is copied.'
            );
            Appeal__c appeal = reread(spring.Id);
            Assert.areEqual(
                'The spring letter to every donor.',
                appeal.Description__c,
                'An edit on the Campaign never flows back to the appeal.'
            );
            Assert.areEqual(link, appeal.Campaign_Id__c, 'The link is kept, not replaced.');
        }
    }

    @IsTest
    static void anAppealThatAlreadyMatchesIsNotWrittenAgain() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Appeal__c spring = springAppeal();
            System.runAs(admin) {
                insert spring;
            }
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            CampaignSyncService.Result result;
            Test.startTest();
            System.runAs(admin) {
                result = CampaignSyncService.syncSaved(new List<Appeal__c>{ reread(spring.Id) });
            }
            Test.stopTest();
            Assert.areEqual(1, result.unchanged, 'Nothing changed, so nothing is written.');
            Assert.areEqual(0, result.updated + result.created + result.failed, 'No DML at all.');
        }
    }

    @IsTest
    static void aChildAppealsCampaignSitsUnderItsParentsCampaign() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Appeal__c gala = new Appeal__c(Name = 'Capital campaign', Active__c = true);
            System.runAs(admin) {
                insert gala;
            }
            Appeal__c calls = new Appeal__c(
                Name = 'Capital campaign: major donor calls',
                Active__c = true,
                Parent_Appeal__c = gala.Id
            );
            Test.startTest();
            System.runAs(admin) {
                insert calls;
            }
            Test.stopTest();
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            Assert.areEqual(
                Id.valueOf(reread(gala.Id).Campaign_Id__c),
                campaign(reread(calls.Id).Campaign_Id__c).get('ParentId'),
                'Parent Appeal becomes Parent Campaign (R-CS2).'
            );
        }
    }

    @IsTest
    static void aParentLinkedInTheSameCallIsPutAboveItsChild() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            switchOn(false);
            Appeal__c parent = new Appeal__c(Name = 'Year-end', Active__c = true);
            insert parent;
            Appeal__c child = new Appeal__c(
                Name = 'Year-end: second letter',
                Active__c = true,
                Parent_Appeal__c = parent.Id
            );
            insert child;
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            // Neither has a Campaign yet: both were saved while the sync was off. Maria's catch-up
            // copies the child before the parent, which is the order that needs the second update.
            switchOn(true);

            Test.startTest();
            System.runAs(admin) {
                CampaignSyncService.syncSaved(
                    new List<Appeal__c>{ reread(child.Id), reread(parent.Id) }
                );
            }
            Test.stopTest();
            Assert.areEqual(
                Id.valueOf(reread(parent.Id).Campaign_Id__c),
                campaign(reread(child.Id).Campaign_Id__c).get('ParentId'),
                'The child is put under a parent whose Campaign was made later in the same call.'
            );
        }
    }

    @IsTest
    static void switchedOffNothingIsCopied() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            switchOn(false);
            Appeal__c spring = springAppeal();
            Test.startTest();
            System.runAs(maria()) {
                insert spring;
            }
            Test.stopTest();
            Assert.isNull(reread(spring.Id).Campaign_Id__c, 'Off at install, and off means off.');
        }
    }

    @IsTest
    static void davidWithoutCampaignAccessStillSavesHisAppeal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'Giving_Staff' });
            Appeal__c spring = springAppeal();
            CampaignSyncService.Result result;
            Test.startTest();
            System.runAs(david) {
                insert spring;
                result = CampaignSyncService.syncBeforeSave(
                    new List<Appeal__c>{ springAppeal() },
                    null
                );
            }
            Test.stopTest();
            Assert.isNull(reread(spring.Id).Campaign_Id__c, 'The appeal saves without a Campaign.');
            if (CampaignSyncService.isAvailable()) {
                Assert.areEqual(
                    1,
                    result.skipped,
                    'It is skipped and logged, not refused (R-CS4).'
                );
            }
        }
    }

    @IsTest
    static void davidIsLoggedOnceWhenHeCreatesAppealsAndNotWhenHeEditsThem() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'Giving_Staff' });
            switchOn(false);
            Appeal__c existing = springAppeal();
            insert existing;
            switchOn(true);
            Test.startTest();
            System.runAs(david) {
                insert new Appeal__c(Name = 'Autumn appeal', Active__c = true);
                insert new Appeal__c(Name = 'Winter appeal', Active__c = true);
                update new Appeal__c(Id = existing.Id, Goal__c = 26000);
                update new Appeal__c(Id = existing.Id, Goal__c = 27000);
            }
            Test.stopTest();
            Assert.areEqual(
                CampaignSyncService.isAvailable() ? 1 : 0,
                countWarnings(),
                'One Warning when David creates appeals, none for his edits (R-CS4).'
            );
        }
    }

    @IsTest
    static void twoHundredRefusedCampaignsCostOneLogWrite() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            // 200 appeals linked, while the sync was off, to Campaigns that are then deleted: each
            // copy is refused, which is what a validation rule on Campaign does to a whole import.
            switchOn(false);
            List<SObject> gone = new List<SObject>();
            for (Integer i = 0; i < 200; i++) {
                SObject doomed = CampaignSyncService.campaignType().newSObject();
                doomed.put('Name', 'Giving day ' + i);
                gone.add(doomed);
            }
            System.runAs(admin) {
                insert gone;
            }
            List<Appeal__c> appeals = new List<Appeal__c>();
            for (Integer i = 0; i < 200; i++) {
                appeals.add(
                    new Appeal__c(
                        Name = 'Giving day ' + i,
                        Active__c = true,
                        Campaign_Id__c = String.valueOf(gone[i].Id)
                    )
                );
            }
            System.runAs(admin) {
                // As Maria, who holds the Campaign ID field; the sync is off, so nothing is copied.
                insert appeals;
                delete gone;
            }
            switchOn(true);
            for (Appeal__c appeal : appeals) {
                appeal.Goal__c = 1000;
            }

            Test.startTest();
            Integer logWritesBefore = Limits.getPublishImmediateDML();
            System.runAs(admin) {
                update appeals;
            }
            Integer logWrites = Limits.getPublishImmediateDML() - logWritesBefore;
            Test.stopTest();

            Assert.areEqual(
                1,
                logWrites,
                'Two hundred refusals are logged in one statement (R-CS5).'
            );
            Assert.areEqual(200, countWarnings(), 'Each refused appeal still has its own Warning.');
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Appeal__c WHERE Goal__c = 1000 WITH SYSTEM_MODE],
                'Every appeal saved all the same.'
            );
        }
    }

    @IsTest
    static void aSaveTooLargeToCopyIsSavedUncopiedAndLoggedOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Assert.isTrue(CampaignSyncService.hasHeadroom(200), 'A fresh transaction has room.');
            ConnectSync.simulatedQueriesUsed = Limits.getLimitQueries() - 5;
            List<Appeal__c> first = new List<Appeal__c>{ springAppeal() };
            List<Appeal__c> second = new List<Appeal__c>{
                new Appeal__c(Name = 'Autumn appeal', Active__c = true)
            };
            Test.startTest();
            System.runAs(admin) {
                insert first;
                insert second;
            }
            Test.stopTest();
            Assert.isNull(reread(first[0].Id).Campaign_Id__c, 'The appeal saves, uncopied.');
            Assert.isNull(reread(second[0].Id).Campaign_Id__c, 'So does the next one.');
            Assert.areEqual(
                CampaignSyncService.isAvailable() ? 1 : 0,
                countWarnings(),
                'One Warning for the transaction, not one per save (R-CS5).'
            );

            ConnectSync.simulatedQueriesUsed = null;
            ConnectSync.simulatedDmlStatementsUsed = Limits.getLimitDmlStatements() - 5;
            Assert.isFalse(
                CampaignSyncService.hasHeadroom(1),
                'Running out of DML statements stops the copy too.'
            );
        }
    }

    @IsTest
    static void aCampaignWrittenForAnAppealThatFailsIsRolledBackWithIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Appeal__c spring = springAppeal();
            System.runAs(admin) {
                insert spring;
            }
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            String taken = reread(spring.Id).Campaign_Id__c;
            Integer campaignsBefore = countCampaigns();
            // The second appeal pastes a Campaign ID the first already holds, so the database
            // refuses it after the copy has run; the platform then retries the rest without it.
            Appeal__c fresh = new Appeal__c(Name = 'Autumn appeal', Active__c = true);
            Appeal__c duplicate = new Appeal__c(Name = 'Stolen name', Campaign_Id__c = taken);
            List<Database.SaveResult> saved;
            Test.startTest();
            System.runAs(admin) {
                saved = Database.insert(new List<Appeal__c>{ fresh, duplicate }, false);
            }
            Test.stopTest();
            Assert.isTrue(saved[0].isSuccess(), 'The good appeal saves.');
            Assert.isFalse(saved[1].isSuccess(), 'A Campaign ID can belong to one appeal (R-CS8).');
            Assert.areEqual(
                'Spring appeal',
                campaign(taken).get('Name'),
                'The failed appeal is not written onto the Campaign: its copy is rolled back with it.'
            );
            Assert.areEqual(
                campaignsBefore + 1,
                countCampaigns(),
                'Only the saved appeal has a new Campaign; the first attempt\'s is rolled back.'
            );
            Assert.isNotNull(reread(fresh.Id).Campaign_Id__c, 'The saved appeal is linked.');
        }
    }

    @IsTest
    static void aTypedValueThatIsNotACampaignIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!CampaignSyncService.isAvailable()) {
                return;
            }
            Account notACampaign = new Account(Name = 'Riverside Foundation');
            insert notACampaign;
            Appeal__c spring = springAppeal();
            spring.Campaign_Id__c = notACampaign.Id;
            Test.startTest();
            Database.SaveResult saved;
            System.runAs(maria()) {
                saved = Database.insert(spring, false);
            }
            Test.stopTest();
            Assert.isFalse(saved.isSuccess(), 'An Account identifier is not a Campaign (R-CS8).');
            Assert.areEqual(
                Label.Connect_CampaignSync_InvalidCampaignId,
                saved.getErrors()[0].getMessage(),
                'The refusal says what the field must hold.'
            );
        }
    }

    @IsTest
    static void pastingAnExistingCampaignLinksToItAndWritesTheAppealOntoIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            SObject existing = CampaignSyncService.campaignType().newSObject();
            existing.put('Name', 'Spring mailing (old)');
            System.runAs(admin) {
                insert existing;
            }
            Appeal__c spring = springAppeal();
            spring.Campaign_Id__c = String.valueOf(existing.Id).left(15);
            Test.startTest();
            System.runAs(admin) {
                insert spring;
            }
            Test.stopTest();
            Appeal__c saved = reread(spring.Id);
            Assert.areEqual(
                String.valueOf(existing.Id),
                saved.Campaign_Id__c,
                'A 15 character identifier is stored in its 18 character form.'
            );
            Assert.areEqual(
                'Spring appeal',
                campaign(saved.Campaign_Id__c).get('Name'),
                'The appeal is written onto the Campaign it was linked to.'
            );
        }
    }

    @IsTest
    static void aDeletedCampaignIsReportedAndTheAppealStillSaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User admin = maria();
            Appeal__c spring = springAppeal();
            System.runAs(admin) {
                insert spring;
            }
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            Appeal__c saved = reread(spring.Id);
            System.runAs(admin) {
                delete CampaignSyncService.campaignType()
                    .newSObject(Id.valueOf(saved.Campaign_Id__c));
            }
            Appeal__c edited = saved.clone(true, true, true, true);
            edited.Goal__c = 40000;
            CampaignSyncService.Result result;
            Test.startTest();
            System.runAs(admin) {
                result = CampaignSyncService.syncBeforeSave(
                    new List<Appeal__c>{ edited },
                    new Map<Id, Appeal__c>{ saved.Id => saved }
                );
                update new Appeal__c(Id = spring.Id, Goal__c = 40000);
            }
            Test.stopTest();
            Assert.areEqual(1, result.failed, 'Reported, not replaced (R-CS7).');
            Assert.areEqual(0, result.created, 'No second Campaign is made for the appeal.');
            Assert.areEqual(40000, reread(spring.Id).Goal__c, 'The appeal saved all the same.');
        }
    }

    @IsTest
    static void twoHundredAppealsInOneSaveEachGetACampaign() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Appeal__c> appeals = new List<Appeal__c>();
            for (Integer i = 0; i < 200; i++) {
                appeals.add(new Appeal__c(Name = 'Giving day ' + i, Goal__c = i, Active__c = true));
            }
            Test.startTest();
            System.runAs(maria()) {
                insert appeals;
            }
            Test.stopTest();
            if (!CampaignSyncService.isAvailable()) {
                assertNoAppealLinked();
                return;
            }
            Integer linked = [
                SELECT COUNT()
                FROM Appeal__c
                WHERE Id IN :appeals AND Campaign_Id__c != NULL
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(200, linked, 'One insert of Campaigns serves the whole save.');
        }
    }

    @IsTest
    static void comparisonsReadAsAPersonWould() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(ConnectSync.same(100, 100.00), 'Amounts compare by value.');
            Assert.isFalse(ConnectSync.same('Gala', 'gala'), 'Text compares with case.');
            Assert.isTrue(ConnectSync.same(null, null), 'Two empties are the same.');
            Assert.isFalse(ConnectSync.same(null, ''), 'Empty and blank text differ.');
        }
    }
}
