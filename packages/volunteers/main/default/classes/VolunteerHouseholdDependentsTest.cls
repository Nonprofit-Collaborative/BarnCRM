/**
 * Volunteer hours keep the household they were given in (R-VG2, R-H12, ADR-0070, ADR-0071): the
 * empty household tidy-up finds `VolunteersHouseholdDependentsExtension` by name and keeps a
 * household hours are credited to, a household with none is still tidied away, and a household
 * merge moves the hours to the household kept. Run as a BarnCRM admin holding Volunteers Admin,
 * the person who moves and merges households.
 */
@IsTest(testFor='ApexClass:VolunteersHouseholdDependentsExtension')
private class VolunteerHouseholdDependentsTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            VolunteersTestData.job('Food pantry sort');
            insert new List<Contact>{
                HouseholdTestDataFactory.newContact('Ana', 'Nolan'),
                HouseholdTestDataFactory.newContact('Wei', 'Lee'),
                HouseholdTestDataFactory.newContact('Sarah', 'Nguyen')
            };
        }
    }

    private static Contact person(String firstName) {
        return [SELECT Id, AccountId FROM Contact WHERE FirstName = :firstName];
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    private static List<Volunteer_Hours__c> hoursFor(Id contactId, Integer howMany) {
        List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
        for (Integer i = 0; i < howMany; i++) {
            entries.add(VolunteersTestData.newHours(contactId, jobId(), 1.5));
        }
        return entries;
    }

    @IsTest
    static void aVolunteerWhoMovesOutLeavesTheirHouseholdAndEveryEntryInPlace() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Contact ana = person('Ana');
            Id leftHousehold = ana.AccountId;
            insert hoursFor(ana.Id, 251);

            Test.startTest();
            HouseholdService.moveContact(ana.Id, person('Wei').AccountId);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :leftHousehold],
                'The household Ana left still has her hours, so the tidy-up keeps it'
            );
            Assert.areEqual(
                251,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Household__c = :leftHousehold],
                'Every entry stays with the household it was given in'
            );
        }
    }

    @IsTest
    static void aHouseholdWithNoHoursIsStillDeleted() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Contact sarah = person('Sarah');
            Id leftHousehold = sarah.AccountId;
            insert hoursFor(person('Ana').Id, 2);

            Test.startTest();
            HouseholdService.moveContact(sarah.Id, person('Wei').AccountId);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :leftHousehold],
                'Nothing is credited to the household Sarah left, so the tidy-up deletes it'
            );
        }
    }

    @IsTest
    static void mergingHouseholdsMovesTheHoursToTheHouseholdKept() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Contact ana = person('Ana');
            Id kept = person('Wei').AccountId;
            insert hoursFor(ana.Id, 3);

            Test.startTest();
            HouseholdMergeService.mergeHouseholds(
                kept,
                ana.AccountId,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Household__c = :kept],
                'The merge moves every entry to the household kept'
            );
        }
    }

    @IsTest
    static void answersOnlyForTheHouseholdsAskedAbout() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Contact ana = person('Ana');
            insert hoursFor(ana.Id, 1);
            Id noHours = person('Wei').AccountId;

            Test.startTest();
            Set<Id> answer = new VolunteersHouseholdDependentsExtension()
                .householdsWithDependents(new Set<Id>{ ana.AccountId, noHours });
            Set<Id> none = new VolunteersHouseholdDependentsExtension()
                .householdsWithDependents(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(new Set<Id>{ ana.AccountId }, answer, 'Only the household with hours');
            Assert.isTrue(none.isEmpty(), 'Asking about no households asks nothing');
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountKeepsTheHouseholdTheirHoursWereGivenIn() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            Account household = VolunteersTestData.household('The Okafor Family');
            insert new Household_Member__c(
                Household__c = household.Id,
                Account__c = person.Id,
                Role__c = 'Head'
            );
            Volunteer_Hours__c entry = VolunteersTestData.newHours(null, jobId(), 2);
            entry.Account__c = person.Id;
            insert entry;

            Test.startTest();
            Set<Id> answer = HouseholdDependentsExtensions.householdsWithDependents(
                new Set<Id>{ household.Id, person.Id }
            );
            Test.stopTest();

            Assert.isTrue(
                answer.contains(household.Id),
                'Core hears that the household the person account gave hours in is credited'
            );
            Assert.isFalse(
                answer.contains(person.Id),
                'The person account itself is a person, not a household hours are credited to'
            );
        }
    }
}
