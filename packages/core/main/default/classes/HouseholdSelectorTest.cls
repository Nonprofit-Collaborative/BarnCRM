/**
 * The household selector's guards and its org-shape branches, read directly rather than through
 * the services that call it.
 *
 * Every read answers an empty question with an empty answer and no query. The native Nonprofit
 * Cloud probes are shown on an org that is said to have the object but cannot query it, which
 * is the shape a licence or permission gap produces: a probe that cannot run must read as "the
 * accounts are dependent" for the delete guard and as "unknown" for Health Check, never as
 * "nothing there" (ADR-0036). Stating the describe also makes those probes fail, so the
 * answers hold in an org that really has the objects (Nonprofit Cloud, Contacts to Multiple
 * Accounts on), and the stated-rows check states an empty describe so no real probe runs.
 */
@IsTest(testFor='ApexClass:HouseholdSelector')
private class HouseholdSelectorTest {
    private static final Set<String> NATIVE_OBJECTS = new Set<String>{
        'PartyRelationshipGroup', // detection-only: names the native objects the probes ask the describe about
        'AccountContactRelation' // detection-only: names the native objects the probes ask the describe about
    };

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void anEmptyQuestionIsAnsweredWithoutAQuery() {
        System.runAs(TestUsers.admin()) {
            Set<Id> none = new Set<Id>();

            Test.startTest();
            for (Set<Id> ids : new List<Set<Id>>{ null, none }) {
                Assert.isTrue(
                    HouseholdSelector.getContactsByHouseholdIds(ids).isEmpty(),
                    'Contacts'
                );
                Assert.isTrue(HouseholdSelector.getContactsByIds(ids).isEmpty(), 'Contacts by id');
                Assert.isTrue(
                    HouseholdSelector.getContactsByHouseholdIdsForDisplay(ids).isEmpty(),
                    'Contacts for display'
                );
                Assert.isTrue(
                    HouseholdSelector.getContactsByIdsForDisplay(ids).isEmpty(),
                    'Contacts by id for display'
                );
                Assert.isTrue(
                    HouseholdSelector.getMembershipsForDisplay(ids).isEmpty(),
                    'Memberships for display'
                );
                Assert.isTrue(HouseholdSelector.getContactsWithHouseholds(ids).isEmpty(), 'Links');
                Assert.isTrue(HouseholdSelector.getHouseholdsByIds(ids).isEmpty(), 'Households');
                Assert.isTrue(
                    HouseholdSelector.getAccountRecordTypes(ids).isEmpty(),
                    'Record types'
                );
                Assert.isTrue(
                    HouseholdSelector.getAccountsWithNativeDependents(ids).isEmpty(),
                    'Native dependents'
                );
                Assert.isTrue(
                    HouseholdSelector.nativeHouseholdAccountsAmong(ids).isEmpty(),
                    'Native households among'
                );
                Assert.isTrue(
                    HouseholdSelector.accountsWithNativeHouseholdGroups(ids).isEmpty(),
                    'Native groups'
                );
                Assert.isTrue(HouseholdSelector.getHouseholdsForMerge(ids).isEmpty(), 'Merge');
                Assert.isTrue(HouseholdSelector.getEditableIds(ids).isEmpty(), 'Editable');
                Assert.isTrue(HouseholdSelector.getMemberships(ids).isEmpty(), 'Memberships');
                Assert.isTrue(
                    HouseholdSelector.getMembershipsForPeople(ids).isEmpty(),
                    'Memberships for people'
                );
                Assert.isTrue(
                    HouseholdSelector.getAllMembershipsForPeople(ids).isEmpty(),
                    'All memberships for people'
                );
                Assert.isTrue(
                    HouseholdSelector.getDeletedMembershipsForPeople(ids).isEmpty(),
                    'Deleted memberships'
                );
                Assert.isTrue(
                    HouseholdSelector.householdsWithAnyContact(ids).isEmpty(),
                    'Occupied households'
                );
                Assert.isTrue(
                    HouseholdSelector.nativeMembershipRows(ids, null).isEmpty(),
                    'Native membership rows'
                );
            }
            Assert.isTrue(
                HouseholdSelector.nativeMembershipRows(new Set<Id>{ UserInfo.getUserId() }, none)
                    .isEmpty(),
                'An empty set of people is not a question about every person'
            );
            Assert.isTrue(
                HouseholdSelector.searchHouseholds('  ', null, 5).isEmpty(),
                'A blank search term finds nothing'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void everyReadAnswersFromTheRecordsItWasAskedAbout() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('Read Household');
            Account empty = HouseholdTestDataFactory.newHousehold('Empty Household');
            insert new List<Account>{ household, empty };
            Contact resident = HouseholdTestDataFactory.newContact('Ria', 'Reader');
            resident.AccountId = household.Id;
            insert resident;
            Household_Member__c ended = new Household_Member__c(
                Household__c = empty.Id,
                Contact__c = resident.Id,
                Start_Date__c = Date.today().addDays(-30),
                End_Date__c = Date.today().addDays(-1)
            );
            insert ended;
            Set<Id> households = new Set<Id>{ household.Id, empty.Id };
            Set<Id> people = new Set<Id>{ resident.Id };

            Test.startTest();
            Assert.areEqual(
                1,
                HouseholdSelector.getContactsByHouseholdIds(households).size(),
                'The resident'
            );
            Assert.areEqual(1, HouseholdSelector.getContactsByIds(people).size(), 'By id');
            Assert.areEqual(
                1,
                HouseholdSelector.getContactsByHouseholdIdsForDisplay(households).size(),
                'For display by household'
            );
            Assert.areEqual(
                1,
                HouseholdSelector.getContactsByIdsForDisplay(people).size(),
                'For display by id'
            );
            Assert.areEqual(
                household.Id,
                HouseholdSelector.getContactsWithHouseholds(people)[0].AccountId,
                'The resident knows the household'
            );
            Assert.areEqual(2, HouseholdSelector.getHouseholdsByIds(households).size(), 'Both');
            Assert.areEqual(2, HouseholdSelector.getAccountRecordTypes(households).size(), 'Types');
            Assert.areEqual(
                2,
                HouseholdSelector.getHouseholdsForMerge(households).size(),
                'Merge candidates'
            );
            Assert.areEqual(
                households,
                HouseholdSelector.getEditableIds(households),
                'The administrator may edit both'
            );
            Assert.areEqual(
                1,
                HouseholdSelector.getMemberships(households).size(),
                'An ended membership is not current'
            );
            Assert.areEqual(
                1,
                HouseholdSelector.getMembershipsForDisplay(households).size(),
                'Nor on screen'
            );
            Assert.areEqual(
                1,
                HouseholdSelector.getMembershipsForPeople(people).size(),
                'Current only for the person'
            );
            Assert.areEqual(
                2,
                HouseholdSelector.getAllMembershipsForPeople(people).size(),
                'Every membership, ended or not'
            );
            Assert.areEqual(
                new Set<Id>{ household.Id },
                HouseholdSelector.householdsWithAnyContact(households),
                'Only the household with a resident is occupied'
            );
            delete ended;
            Assert.areEqual(
                1,
                HouseholdSelector.getDeletedMembershipsForPeople(people).size(),
                'A deleted membership is found among the deleted'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void statedAnswersAreReturnedInPlaceOfAQuery() {
        System.runAs(TestUsers.admin()) {
            Id anyAccount = UserInfo.getOrganizationId();
            Set<Id> stated = new Set<Id>{ anyAccount };
            HouseholdSelector.accountsWithNativeDependentsOverride = stated;
            HouseholdSelector.accountsWithNativeHouseholdGroupsOverride = stated;
            HouseholdSelector.nativeHouseholdCollisionCountOverride = 4;
            HouseholdSelector.nativeMembershipRowsOverride = new List<HouseholdSelector.NativeMembership>{
                new HouseholdSelector.NativeMembership(anyAccount, anyAccount, anyAccount, true)
            };

            Assert.areEqual(stated, HouseholdSelector.getAccountsWithNativeDependents(null), 'A');
            Assert.areEqual(stated, HouseholdSelector.accountsWithNativeHouseholdGroups(null), 'B');
            Assert.areEqual(4, HouseholdSelector.nativeHouseholdCollisionCount(), 'C');
            Assert.areEqual(1, HouseholdSelector.nativeMembershipRows(null, null).size(), 'D');

            HouseholdSelector.accountsWithNativeDependentsOverride = null;
            HouseholdSelector.nativeMembershipAccountsOverride = stated;
            HouseholdSelector.describedObjectNamesOverride = new Set<String>();
            OrgShapeDetector.reset();
            OrgShapeSelector.nativeHouseholdGroupCountOverride = 2;
            Assert.areEqual(
                stated,
                HouseholdSelector.getAccountsWithNativeDependents(
                    new Set<Id>{ anyAccount, UserInfo.getUserId() }
                ),
                'Only the accounts the stated rows name are dependent'
            );
        }
    }

    @IsTest
    static void aSearchTermIsMatchedLiterallyAndLimited() {
        System.runAs(TestUsers.admin()) {
            Account match = HouseholdTestDataFactory.newHousehold('Q_100% Match');
            Account lookalike = HouseholdTestDataFactory.newHousehold('Qx1000 Match');
            insert new List<Account>{ match, lookalike };

            Test.startTest();
            List<Account> found = HouseholdSelector.searchHouseholds('q_100%', null, null);
            List<Account> skipped = HouseholdSelector.searchHouseholds('q_100%', match.Id, 0);
            Test.stopTest();

            Assert.areEqual(1, found.size(), 'The wildcard characters are not wildcards');
            Assert.areEqual(match.Id, found[0].Id, 'Only the literal match is found');
            Assert.isTrue(skipped.isEmpty(), 'The household being merged is not offered');
        }
    }

    @IsTest
    static void theRecomputeLocatorIsBuiltOverHouseholdsWithoutACustomName() {
        System.runAs(TestUsers.admin()) {
            Account named = HouseholdTestDataFactory.newHousehold('Named Household');
            Account custom = HouseholdTestDataFactory.newHousehold('Custom Household');
            custom.Custom_Name__c = true;
            insert new List<Account>{ named, custom };

            Test.startTest();
            Set<Id> located = new Set<Id>();
            Database.QueryLocatorIterator rows = HouseholdSelector.getHouseholdsForRecomputeLocator()
                .iterator();
            while (rows.hasNext()) {
                located.add(((Account) rows.next()).Id);
            }
            Test.stopTest();

            Assert.isTrue(located.contains(named.Id), 'A generated name is recomputed');
            Assert.isFalse(located.contains(custom.Id), 'A custom name is left alone');
        }
    }

    @IsTest
    static void aProbeThatCannotRunMakesEveryAccountADependent() {
        System.runAs(TestUsers.admin()) {
            Account household = HouseholdTestDataFactory.newHousehold('Probe Household');
            Account other = HouseholdTestDataFactory.newHousehold('Other Household');
            insert new List<Account>{ household, other };
            Set<Id> ids = new Set<Id>{ household.Id, other.Id };
            HouseholdSelector.describedObjectNamesOverride = NATIVE_OBJECTS;
            OrgShapeDetector.reset();
            OrgShapeSelector.nativeHouseholdGroupCountOverride = 2;

            Test.startTest();
            Set<Id> dependents = HouseholdSelector.getAccountsWithNativeDependents(ids);
            Set<Id> grouped = HouseholdSelector.accountsWithNativeHouseholdGroups(ids);
            Set<Id> among = HouseholdSelector.nativeHouseholdAccountsAmong(ids);
            Test.stopTest();

            Assert.areEqual(
                ids,
                dependents,
                'A probe that fails is treated as every account being dependent, so nothing is deleted'
            );
            Assert.areEqual(ids, grouped, 'The same holds for the duplicate scan and the merge');
            Assert.areEqual(ids, among, 'And for the household guard');
        }
    }

    @IsTest
    static void anObjectThatIsNotDescribedIsNotProbed() {
        System.runAs(TestUsers.admin()) {
            Account household = HouseholdTestDataFactory.newHousehold('Plain Household');
            insert household;
            Set<Id> ids = new Set<Id>{ household.Id };
            HouseholdSelector.describedObjectNamesOverride = new Set<String>();
            OrgShapeDetector.reset();
            OrgShapeSelector.nativeHouseholdGroupCountOverride = 2;

            Test.startTest();
            Set<Id> dependents = HouseholdSelector.getAccountsWithNativeDependents(ids);
            Integer collisions = HouseholdSelector.nativeHouseholdCollisionCount();
            List<HouseholdSelector.NativeMembership> rows = HouseholdSelector.nativeMembershipRows(
                ids,
                null
            );
            Test.stopTest();

            Assert.isTrue(dependents.isEmpty(), 'No native object, nothing depends on it');
            Assert.areEqual(0, collisions, 'No native households to collide with');
            Assert.isTrue(rows.isEmpty(), 'No native membership rows');
        }
    }

    @IsTest
    static void aCollisionCountThatCannotBeAskedIsUnknownNotZero() {
        System.runAs(TestUsers.admin()) {
            HouseholdSelector.describedObjectNamesOverride = NATIVE_OBJECTS;

            Test.startTest();
            Integer collisions = HouseholdSelector.nativeHouseholdCollisionCount();
            Test.stopTest();

            Assert.isNull(
                collisions,
                'Health Check decides what to say about unknown, so the selector does not say zero'
            );
        }
    }

    @IsTest
    static void nativeMembershipRowsAreQueriedForAccountsAndForPairs() {
        System.runAs(TestUsers.admin()) {
            Account household = HouseholdTestDataFactory.newHousehold('Rows Household');
            insert household;
            Contact person = HouseholdTestDataFactory.newContact('Rowan', 'Rows');
            insert person;
            HouseholdSelector.describedObjectNamesOverride = NATIVE_OBJECTS;

            Integer failed = 0;
            for (Set<Id> people : new List<Set<Id>>{ null, new Set<Id>{ person.Id } }) {
                try {
                    HouseholdSelector.nativeMembershipRows(new Set<Id>{ household.Id }, people);
                } catch (Exception queryFailed) {
                    failed++;
                }
            }

            Assert.areEqual(
                2,
                failed,
                'On an org where the object is said to exist but cannot be queried, both reads ' +
                'ask the platform and surface its refusal'
            );
        }
    }
}
