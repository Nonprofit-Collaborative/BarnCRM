/**
 * What a merge of two people does to their giving (C-20, R-DP4). The platform's merge moves
 * every gift and soft credit that named the merged-away person onto the survivor without
 * saving them, so no gift trigger runs. The real-time totals that target people are
 * recalculated at once (RollupService.runAfterMerge), and the household each gift was
 * credited to is kept, because the merge never tidies a household away.
 *
 * It runs the real engine over the real shipped definitions, because the thing under test is
 * that the survivor's total includes what the merge moved onto it.
 */
@IsTest(testFor='ApexClass:RollupService')
private class GivingContactMergeTest {
    @IsTest
    static void theSurvivorGetsTheOtherPersonsGiftsCreditsAndTotal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            RollupService.ensureDefaults();
            Contact ana = GivingTestDataFactory.insertHouseholdContact(
                'The Okafor Family',
                'Ana',
                'Okafor'
            );
            Contact bea = GivingTestDataFactory.insertHouseholdContact(
                'The Lindqvist Family',
                'Bea',
                'Lindqvist'
            );
            Contact wei = GivingTestDataFactory.insertHouseholdContact(
                'The Lee Family',
                'Wei',
                'Lee'
            );
            Gift__c hers = GivingTestDataFactory.buildGift(ana.Id, 100);
            Gift__c other = GivingTestDataFactory.buildGift(bea.Id, 50);
            Gift__c solicited = GivingTestDataFactory.buildGift(wei.Id, 500);
            insert new List<Gift__c>{ hers, other, solicited };
            Soft_Credit__c credit = new Soft_Credit__c(
                Gift__c = solicited.Id,
                Contact__c = bea.Id,
                Role__c = 'Solicitor',
                Amount__c = 500
            );
            insert credit;

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Gift__c moved = [
                SELECT Donor_Contact__c, Household__c
                FROM Gift__c
                WHERE Id = :other.Id
            ];
            Assert.areEqual(ana.Id, moved.Donor_Contact__c, 'Bea\'s gift is now Ana\'s.');
            Assert.areEqual(
                bea.AccountId,
                moved.Household__c,
                'It keeps the household it was credited to: the merge tidied nothing away.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :bea.AccountId],
                'That household is still there, for a person to merge into Ana\'s.'
            );
            Assert.areEqual(
                ana.Id,
                [SELECT Contact__c FROM Soft_Credit__c WHERE Id = :credit.Id].Contact__c,
                'Bea\'s soft credit is now Ana\'s.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
                'The survivor is recalculated in the same save, never by a batch over every gift.'
            );
            Contact survivor = [SELECT Total_Giving__c FROM Contact WHERE Id = :ana.Id];
            GivingTestDataFactory.assertRollupWrote(survivor.Total_Giving__c);
            Assert.areEqual(
                150,
                survivor.Total_Giving__c,
                'Ana\'s total includes the gift the merge moved onto her, without waiting a night.'
            );
        }
    }
}
