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
