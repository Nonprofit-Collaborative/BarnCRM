/**
 * A gift keeps the household it was given to, even when the donor was the last to leave it
 * and the empty household tidy-up is on (R-G2, R-H12, ADR-NEXT
 * `NEXT-empty-household-tidy-up-keeps-households-with-gifts.md`). End to end: Core's tidy-up
 * finds `GivingHouseholdDependentsExtension` by name and keeps what it reports.
 */
@IsTest
private class GivingHouseholdDependentsExtensionTest {
    @TestSetup
    static void makeData() {
        TestDataFactory.defaultSettings();
        GivingTestDataFactory.insertDefaultFund();
        insert new List<Contact>{
            new Contact(FirstName = 'Ana', LastName = 'Nolan'),
            new Contact(FirstName = 'Wei', LastName = 'Lee'),
            new Contact(FirstName = 'Sarah', LastName = 'Nguyen')
        };
    }

    private static Contact person(String firstName) {
        return [SELECT Id, AccountId FROM Contact WHERE FirstName = :firstName];
    }

    @IsTest
    static void aDonorWhoMovesOutLeavesTheirHouseholdAndEveryGiftInPlace() {
        Contact ana = person('Ana');
        Id leftHousehold = ana.AccountId;
        Id newHousehold = person('Wei').AccountId;
        insert GivingTestDataFactory.buildGifts(ana.Id, 200, 25);

        Test.startTest();
        HouseholdService.moveContact(ana.Id, newHousehold);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id = :leftHousehold],
            'The household Ana left still has her gifts, so the tidy-up keeps it'
        );
        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Gift__c WHERE Household__c = :leftHousehold],
            'Every gift stays with the household it was given from'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Gift__c WHERE Household__c != :leftHousehold],
            'No gift moved with Ana or lost its household'
        );
    }

    @IsTest
    static void aHouseholdWithAPledgeAndNoGiftsIsKept() {
        Contact sarah = person('Sarah');
        Id leftHousehold = sarah.AccountId;
        insert new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = sarah.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.newInstance(2026, 10, 1),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );

        Test.startTest();
        HouseholdService.moveContact(sarah.Id, person('Wei').AccountId);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id = :leftHousehold],
            'A pledge is credited to the household too, so it is kept'
        );
        Assert.areEqual(
            leftHousehold,
            [SELECT Household__c FROM Commitment__c WHERE Donor_Contact__c = :sarah.Id]
            .Household__c,
            'The pledge keeps the household it was made to'
        );
    }

    @IsTest
    static void aHouseholdWithNoGiftsIsStillDeleted() {
        Contact sarah = person('Sarah');
        Id leftHousehold = sarah.AccountId;
        insert GivingTestDataFactory.buildGifts(person('Ana').Id, 2, 25);

        Test.startTest();
        HouseholdService.moveContact(sarah.Id, person('Wei').AccountId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Id = :leftHousehold],
            'Nothing is credited to the household Sarah left, so the tidy-up deletes it'
        );
    }

    @IsTest
    static void answersOnlyForTheHouseholdsAskedAbout() {
        Contact ana = person('Ana');
        insert GivingTestDataFactory.buildGift(ana.Id, 25);
        Id emptyOfGifts = person('Wei').AccountId;

        Test.startTest();
        Set<Id> answer = new GivingHouseholdDependentsExtension()
            .householdsWithDependents(new Set<Id>{ ana.AccountId, emptyOfGifts });
        Set<Id> none = new GivingHouseholdDependentsExtension()
            .householdsWithDependents(new Set<Id>());
        Test.stopTest();

        Assert.areEqual(new Set<Id>{ ana.AccountId }, answer, 'Only the household with a gift');
        Assert.isTrue(none.isEmpty(), 'Asking about no households asks nothing');
    }
}
