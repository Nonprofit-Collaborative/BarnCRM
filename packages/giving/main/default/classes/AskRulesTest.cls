/**
 * The ask rules on every save (canonical model R-SO1 to R-SO4): the first stage by default, only
 * stages in the list, stage and closed dates in step, and one donor.
 */
@IsTest(testFor='ApexClass:AskRules, ApexClass:AskTriggerHandler')
private class AskRulesTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith('Giving_Staff');
        TestUsers.adminWith('Giving_Admin');
    }

    private static User staff() {
        return TestUsers.adminWith('Giving_Staff');
    }

    /** The setting is the administrator's, so it is written here in system mode. */
    private static void useStages(String stages) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.Ask_Stages__c = stages;
        if (settings.Id == null) {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
        }
        Database.upsert(settings, true, AccessLevel.SYSTEM_MODE);
    }

    private static Contact person() {
        Contact donor = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
        insert donor;
        return donor;
    }

    @IsTest
    static void parsesTheListInOrderAndOnce() {
        // runs-as: deploying user (pure logic: parses a setting value, no DML or SOQL)
        List<String> stages = AskRules.parse(' Identified ;Qualified;; identified;\nAsked ');
        Assert.areEqual(
            new List<String>{ 'Identified', 'Qualified', 'Asked' },
            stages,
            'Trimmed, empty entries dropped, a repeat kept once.'
        );
        Assert.isTrue(AskRules.parse(null).isEmpty(), 'Nothing in, nothing out.');
    }

    @IsTest
    static void anEmptySettingMeansTheShippedList() {
        System.runAs(staff()) {
            Assert.areEqual(
                AskRules.parse(AskRules.DEFAULT_STAGES),
                AskRules.stages(),
                'The shipped stages.'
            );
        }
    }

    @IsTest
    static void aNewAskStartsAtTheFirstStageAndOpen() {
        System.runAs(staff()) {
            useStages('Prospect;Meeting;Proposal');
            Contact donor = person();

            Test.startTest();
            Ask__c ask = new Ask__c(Donor_Contact__c = donor.Id, Amount__c = 2500);
            insert ask;
            Test.stopTest();

            Ask__c saved = [
                SELECT Stage__c, Outcome__c, Stage_Changed_Date__c, Closed_Date__c
                FROM Ask__c
                WHERE Id = :ask.Id
            ];
            Assert.areEqual('Prospect', saved.Stage__c, 'The first stage.');
            Assert.areEqual(AskRules.OUTCOME_OPEN, saved.Outcome__c, 'Open.');
            Assert.areEqual(
                System.today(),
                saved.Stage_Changed_Date__c,
                'In this stage from today.'
            );
            Assert.isNull(saved.Closed_Date__c, 'Not closed.');
        }
    }

    @IsTest
    static void aStageIsMatchedIgnoringCapitalsAndAStrangeOneIsRefused() {
        System.runAs(staff()) {
            useStages('Prospect;Meeting;Proposal');
            Contact donor = person();
            Ask__c ask = new Ask__c(Donor_Contact__c = donor.Id, Stage__c = 'meeting');
            insert ask;
            Assert.areEqual(
                'Meeting',
                [SELECT Stage__c FROM Ask__c WHERE Id = :ask.Id].Stage__c,
                'Spelled as the list spells it.'
            );

            Test.startTest();
            Database.SaveResult refused = Database.update(
                new Ask__c(Id = ask.Id, Stage__c = 'Negotiating'),
                false,
                AccessLevel.USER_MODE
            );
            Test.stopTest();

            Assert.isFalse(refused.isSuccess(), 'A stage not in the list is refused.');
            Assert.isTrue(
                refused.getErrors()[0].getMessage().contains('Negotiating'),
                'The message names the stage.'
            );
        }
    }

    @IsTest
    static void aStageTakenOutOfTheListDoesNotBlockOtherEdits() {
        System.runAs(staff()) {
            useStages('Prospect;Meeting;Proposal');
            Contact donor = person();
            Ask__c ask = new Ask__c(Donor_Contact__c = donor.Id, Stage__c = 'Proposal');
            insert ask;
            useStages('Prospect;Meeting');

            Test.startTest();
            update new Ask__c(Id = ask.Id, Amount__c = 900);
            Test.stopTest();

            Ask__c saved = [SELECT Stage__c, Amount__c FROM Ask__c WHERE Id = :ask.Id];
            Assert.areEqual('Proposal', saved.Stage__c, 'The old stage is kept.');
            Assert.areEqual(900, saved.Amount__c, 'And the edit is saved.');
        }
    }

    @IsTest
    static void closingFillsTheClosedDateAndReopeningClearsIt() {
        System.runAs(staff()) {
            Contact donor = person();
            Ask__c ask = new Ask__c(
                Donor_Contact__c = donor.Id,
                Stage_Changed_Date__c = System.today().addDays(-30)
            );
            insert ask;
            Assert.areEqual(
                System.today().addDays(-30),
                [SELECT Stage_Changed_Date__c FROM Ask__c WHERE Id = :ask.Id].Stage_Changed_Date__c,
                'A stage date given on create is kept, for imported history.'
            );

            Test.startTest();
            update new Ask__c(Id = ask.Id, Outcome__c = AskRules.OUTCOME_DECLINED);
            Date closedOn = [SELECT Closed_Date__c FROM Ask__c WHERE Id = :ask.Id].Closed_Date__c;
            update new Ask__c(Id = ask.Id, Outcome__c = AskRules.OUTCOME_OPEN, Stage__c = 'Asked');
            Test.stopTest();

            Ask__c saved = [
                SELECT Closed_Date__c, Stage_Changed_Date__c
                FROM Ask__c
                WHERE Id = :ask.Id
            ];
            Assert.areEqual(System.today(), closedOn, 'Closed today.');
            Assert.isNull(saved.Closed_Date__c, 'Reopened: no closed date.');
            Assert.areEqual(System.today(), saved.Stage_Changed_Date__c, 'A new stage, today.');
        }
    }

    @IsTest
    static void anAskNeedsExactlyOneDonorButAnOrphanCanStillBeClosed() {
        System.runAs(staff()) {
            Contact donor = person();
            Account organization = GivingTestDataFactory.insertOrganization('Summit Foundation');

            Database.SaveResult neither = Database.insert(
                new Ask__c(Amount__c = 100),
                false,
                AccessLevel.USER_MODE
            );
            Database.SaveResult both = Database.insert(
                new Ask__c(Donor_Contact__c = donor.Id, Donor_Account__c = organization.Id),
                false,
                AccessLevel.USER_MODE
            );
            Assert.isFalse(neither.isSuccess(), 'No donor is refused.');
            Assert.isFalse(both.isSuccess(), 'Two donors are refused.');

            Ask__c ask = new Ask__c(Donor_Account__c = organization.Id);
            insert ask;
            // The donor goes; the lookup clears and the ask stays.
            System.runAs(TestUsers.adminWith('Giving_Admin')) {
                Database.delete(organization.Id, true, AccessLevel.SYSTEM_MODE);
            }

            Test.startTest();
            update new Ask__c(Id = ask.Id, Outcome__c = AskRules.OUTCOME_WITHDRAWN);
            Test.stopTest();

            Assert.areEqual(
                AskRules.OUTCOME_WITHDRAWN,
                [SELECT Outcome__c FROM Ask__c WHERE Id = :ask.Id].Outcome__c,
                'An ask with no donor can still be closed.'
            );
        }
    }
}
