/**
 * The empty household tidy-up asks installed packages which households they still credit
 * records to, and keeps those (R-H12, ADR-0070
 * `0070-empty-household-tidy-up-keeps-households-with-gifts.md`). No other package is
 * present in Core's tests, so a stub extension is injected by class name.
 */
@IsTest(testFor='ApexClass:HouseholdDependentsExtensions')
private class HouseholdDependentsExtensionsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String GIVING = 'GivingHouseholdDependentsExtension';

    /** Answers that every household in `credited` still has records credited to it. */
    private class StubExtension implements HouseholdDependentsExtension {
        private final Set<Id> credited;
        StubExtension(Set<Id> credited) {
            this.credited = credited;
        }
        public Set<Id> householdsWithDependents(Set<Id> householdIds) {
            Set<Id> answer = new Set<Id>(householdIds);
            answer.retainAll(credited);
            return answer;
        }
    }

    /** An installed extension that fails while answering. */
    private class FailingExtension implements HouseholdDependentsExtension {
        public Set<Id> householdsWithDependents(Set<Id> householdIds) {
            throw new System.QueryException('The extension could not answer');
        }
    }

    private static void onlyThisExtension(HouseholdDependentsExtension extension) {
        HouseholdDependentsExtensions.noneForTest = true;
        HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>();
        if (extension != null) {
            HouseholdDependentsExtensions.overrides.put(GIVING, extension);
        }
    }

    private static List<Account> emptyHouseholds(Integer howMany) {
        List<Account> households = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            households.add(HouseholdTestDataFactory.newHousehold('Household ' + i));
        }
        insert households;
        return households;
    }

    @IsTest
    static void aHouseholdAPackageStillCreditsIsKeptWhenItsLastMemberMoves() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
            onlyThisExtension(new StubExtension(new Set<Id>{ fromHousehold }));

            Test.startTest();
            HouseholdService.moveContact(maria.Id, toHousehold);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
                'The household still has records credited to it, so it is kept'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = :ErrorLogger.SEVERITY_INFO],
                'Keeping a household with credited records is ordinary, so nothing is logged'
            );
        }
    }

    @IsTest
    static void twoHundredEmptyHouseholdsKeepOnlyThoseAPackageCredits() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> households = emptyHouseholds(200);
            Set<Id> credited = new Set<Id>();
            for (Integer i = 0; i < households.size(); i += 2) {
                credited.add(households[i].Id);
            }
            onlyThisExtension(new StubExtension(credited));

            Test.startTest();
            HouseholdService.deleteEmptyHouseholds(new Map<Id, Account>(households).keySet());
            Test.stopTest();

            Set<Id> remaining = new Map<Id, Account>(
                    [SELECT Id FROM Account WHERE Id IN :households]
                )
                .keySet();
            Assert.areEqual(credited, remaining, 'Exactly the credited households are kept');
        }
    }

    @IsTest
    static void withNoExtensionInstalledAnEmptyHouseholdIsDeleted() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> households = emptyHouseholds(1);
            onlyThisExtension(null);

            Test.startTest();
            HouseholdService.deleteEmptyHouseholds(new Set<Id>{ households[0].Id });
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :households[0].Id],
                'Nothing is credited to the household, so the tidy-up deletes it'
            );
        }
    }

    @IsTest
    static void anExtensionThatFailsKeepsEveryHouseholdAndIsLogged() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> households = emptyHouseholds(3);
            onlyThisExtension(new FailingExtension());

            Test.startTest();
            HouseholdService.deleteEmptyHouseholds(new Map<Id, Account>(households).keySet());
            Test.stopTest();

            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Account WHERE Id IN :households],
                'An extension that could not answer has not said the households are safe to delete'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'HouseholdDependentsExtensions.householdsWithDependents'
                ],
                'The failure is logged once'
            );
        }
    }

    @IsTest
    static void anUnusableExtensionKeepsEveryHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Set<Id> asked = new Map<Id, Account>(emptyHouseholds(2)).keySet();

            Test.startTest();
            Set<Id> answer = new HouseholdDependentsExtensions.EveryHouseholdDependent()
                .householdsWithDependents(asked);
            Set<Id> none = HouseholdDependentsExtensions.householdsWithDependents(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(asked, answer, 'An extension that cannot be built keeps everything');
            Assert.isTrue(none.isEmpty(), 'Asking about no households asks nothing');
        }
    }
}
