/**
 * Erasing a donor with Giving installed: gifts and totals stay credited to the anonymous record,
 * the household their gifts were given from is kept and anonymized, and the text Giving holds
 * about them is emptied. Runs through Core's `PersonErasure`, which finds this extension by name.
 */
@IsTest(testFor='ApexClass:GivingPersonErasureExtension')
private class GivingPersonErasureExtensionTest {
    private static User eraser() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Admin', 'BarnCRM_Erase_People' }
        );
    }

    private static Contact donor() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        GivingTestDataFactory.ensureDefaultFund();
        return GivingTestDataFactory.insertHouseholdContact('The Lee Family', 'Jordan', 'Lee');
    }

    @IsTest
    static void keepsGiftsAndEmptiesWhatGivingHoldsAboutThePerson() {
        System.runAs(eraser()) {
            Contact jordan = donor();
            Contact friend = GivingTestDataFactory.insertHouseholdContact(
                'The Park Family',
                'Ana',
                'Park'
            );
            Gift__c own = GivingTestDataFactory.buildGift(jordan.Id, 100);
            Gift__c friends = GivingTestDataFactory.buildGift(friend.Id, 50);
            insert new List<Gift__c>{ own, friends };
            Tribute__c ownWords = new Tribute__c(
                Gift__c = own.Id,
                Type__c = 'In honor of',
                Honoree_Name__c = 'Grandma',
                Message__c = 'With love from Jordan'
            );
            Tribute__c namesJordan = new Tribute__c(
                Gift__c = friends.Id,
                Type__c = 'In honor of',
                Honoree_Contact__c = jordan.Id,
                Honoree_Name__c = 'Jordan Lee'
            );
            insert new List<Tribute__c>{ ownWords, namesJordan };
            Acknowledgment__c sent = new Acknowledgment__c(
                Gift__c = own.Id,
                Channel__c = 'Email',
                Status__c = 'Sent',
                Recipient_Contact__c = jordan.Id,
                Recipient_Email__c = 'jordan@example.invalid',
                Gift_Key__c = 'erase-test-1'
            );
            // The ledger is written by Giving's own jobs, never by a person (ADR-0032).
            Database.insert(sent, true, AccessLevel.SYSTEM_MODE);
            Stewardship_Plan__c plan = new Stewardship_Plan__c(
                Contact__c = jordan.Id,
                Status__c = StewardshipService.STATUS_RUNNING,
                Started_Date__c = System.today()
            );
            insert plan;
            Id householdId = [SELECT Household__c FROM Gift__c WHERE Id = :own.Id].Household__c;

            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            Gift__c kept = [
                SELECT Donor_Contact__c, Amount__c, Household__c
                FROM Gift__c
                WHERE Id = :own.Id
            ];
            Assert.areEqual(
                jordan.Id,
                kept.Donor_Contact__c,
                'Still credited to the anonymous record'
            );
            Assert.areEqual(100, kept.Amount__c, 'Amount kept');
            Assert.areEqual(householdId, kept.Household__c, 'Still given from its household');
            Account household = [SELECT Name FROM Account WHERE Id = :householdId];
            Assert.areEqual(
                Label.Core_Erase_HouseholdName,
                household.Name,
                'Kept for the gift, and anonymized'
            );
            Assert.isNull(
                [SELECT Message__c FROM Tribute__c WHERE Id = :ownWords.Id].Message__c,
                'Their words emptied'
            );
            Assert.areEqual(
                'Grandma',
                [SELECT Honoree_Name__c FROM Tribute__c WHERE Id = :ownWords.Id].Honoree_Name__c,
                'Someone else is not erased'
            );
            Assert.isNull(
                [SELECT Honoree_Name__c FROM Tribute__c WHERE Id = :namesJordan.Id].Honoree_Name__c,
                'Their name emptied'
            );
            Assert.isNull(
                [SELECT Recipient_Email__c FROM Acknowledgment__c WHERE Id = :sent.Id]
                .Recipient_Email__c,
                'Ledger email emptied'
            );
            Assert.areEqual(
                StewardshipService.STATUS_CANCELLED,
                [SELECT Status__c FROM Stewardship_Plan__c WHERE Id = :plan.Id].Status__c,
                'Plan cancelled'
            );
            Boolean giftsReported = false;
            for (PersonErasure.Change change : result.getChanges()) {
                giftsReported |=
                    change.getAction() == PersonErasure.KEPT &&
                    change.getObjectLabel() ==
                    Gift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getLabelPlural();
            }
            Assert.isTrue(giftsReported, 'The kept gifts are listed');
        }
    }

    /** R-SO8: next steps emptied, open asks withdrawn, closed asks keep their outcome. */
    @IsTest
    static void withdrawsOpenAsksAndEmptiesTheirNextSteps() {
        System.runAs(eraser()) {
            Contact jordan = donor();
            Ask__c open = new Ask__c(
                Donor_Contact__c = jordan.Id,
                Amount__c = 5000,
                Next_Step__c = 'Lunch with Jordan in May'
            );
            Ask__c won = new Ask__c(
                Donor_Contact__c = jordan.Id,
                Outcome__c = AskRules.OUTCOME_WON,
                Next_Step__c = 'Thank Jordan at the gala'
            );
            insert new List<Ask__c>{ open, won };

            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            Map<Id, Ask__c> asks = new Map<Id, Ask__c>(
                [SELECT Outcome__c, Next_Step__c, Donor_Contact__c FROM Ask__c]
            );
            Assert.areEqual(
                AskRules.OUTCOME_WITHDRAWN,
                asks.get(open.Id).Outcome__c,
                'Open ask withdrawn'
            );
            Assert.areEqual(AskRules.OUTCOME_WON, asks.get(won.Id).Outcome__c, 'Won ask kept');
            Assert.isNull(asks.get(open.Id).Next_Step__c, 'Next step emptied');
            Assert.isNull(asks.get(won.Id).Next_Step__c, 'Next step emptied on a closed ask');
            Assert.areEqual(jordan.Id, asks.get(won.Id).Donor_Contact__c, 'Ask kept');
            Boolean reported = false;
            for (PersonErasure.Change change : result.getChanges()) {
                reported |=
                    change.getAction() == PersonErasure.ENDED &&
                    change.getObjectLabel() ==
                    Ask__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getLabelPlural();
            }
            Assert.isTrue(reported, 'The asks are listed');
        }
    }

    @IsTest
    static void twoHundredTributesAreEmptiedInOneGo() {
        System.runAs(eraser()) {
            Contact jordan = donor();
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(jordan.Id, 200, 10);
            insert gifts;
            List<Tribute__c> tributes = new List<Tribute__c>();
            for (Gift__c gift : gifts) {
                tributes.add(
                    new Tribute__c(
                        Gift__c = gift.Id,
                        Type__c = 'In honor of',
                        Honoree_Name__c = 'Grandma',
                        Message__c = 'From Jordan'
                    )
                );
            }
            insert tributes;

            Test.startTest();
            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            // A long text area cannot be filtered in SOQL, so the kept messages are counted here.
            Integer kept = 0;
            for (Tribute__c tribute : [SELECT Message__c FROM Tribute__c]) {
                if (tribute.Message__c != null) {
                    kept++;
                }
            }
            Assert.areEqual(0, kept, 'Every message emptied');
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Gift__c WHERE Donor_Contact__c = :jordan.Id],
                'Every gift kept'
            );
        }
    }

    @IsTest
    static void deletesTheAutomaticHouseholdCreditsAndSaysSo() {
        System.runAs(eraser()) {
            RecognitionTestData.setAutomaticHouseholdCredits(true);
            Contact jordan = donor();
            Contact sam = RecognitionTestData.person('Sam', 'Lee', jordan.AccountId);
            Contact friend = GivingTestDataFactory.insertHouseholdContact(
                'The Park Family',
                'Ana',
                'Park'
            );
            Gift__c samsGift = RecognitionTestData.gift(sam.Id, null, 100);
            Gift__c friendsGift = RecognitionTestData.gift(friend.Id, null, 50);
            Soft_Credit__c manual = RecognitionTestData.manualCredit(
                friendsGift.Id,
                jordan.Id,
                'Solicitor',
                50
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Soft_Credit__c
                    WHERE
                        Gift__c = :samsGift.Id
                        AND Contact__c = :jordan.Id
                        AND Is_Automatic__c = TRUE
                ],
                'Jordan is credited on Sam\'s gift as a household member'
            );

            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Soft_Credit__c
                    WHERE Contact__c = :jordan.Id AND Is_Automatic__c = TRUE
                ],
                'The household credit is deleted'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Soft_Credit__c WHERE Id = :manual.Id],
                'A credit a person entered stays'
            );
            Boolean deletedListed = false;
            for (PersonErasure.Change change : result.getChanges()) {
                deletedListed |=
                    change.getAction() == PersonErasure.DELETED &&
                    change.getObjectLabel() == Label.Giving_Erase_HouseholdCreditsLabel;
            }
            Assert.isTrue(deletedListed, 'The deleted credits are listed as Deleted');
            String details = [SELECT Details__c FROM Erasure__c WHERE Contact__c = :jordan.Id]
            .Details__c;
            String softCredits = Soft_Credit__c.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .getLabelPlural();
            Assert.isTrue(
                details.contains(
                    Label.Core_EraseAction_Deleted +
                        ' | ' +
                        Label.Giving_Erase_HouseholdCreditsLabel +
                        ' | 1'
                ),
                'The Erasure record says the household credit was deleted: ' + details
            );
            Assert.isTrue(
                details.contains(Label.Core_EraseAction_Kept + ' | ' + softCredits + ' | 1'),
                'And counts only the credit that stays as kept: ' + details
            );
        }
    }

    @IsTest
    static void keepsTheDonorLevelFields() {
        // runs-as: deploying user (pure logic: returns field tokens, no DML or SOQL)
        GivingPersonErasureExtension extension = new GivingPersonErasureExtension();
        Assert.isTrue(
            extension.fieldsToKeep(Contact.SObjectType).contains(Contact.Donor_Level__c),
            'Contact'
        );
        Assert.isTrue(
            extension.fieldsToKeep(Account.SObjectType).contains(Account.Donor_Level__c),
            'Account'
        );
    }
}
