/**
 * HouseholdWriter's own contract, called directly: an empty list is a no-op, and a save the
 * platform refuses is logged to the Error Log and never thrown at the person who made the
 * change that triggered the upkeep. Only the merge settle step is allowed to fail loudly,
 * because it runs inside the merge's own savepoint.
 */
@IsTest(testFor='ApexClass:HouseholdWriter')
private class HouseholdWriterTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Integer loggedErrors() {
        return [SELECT COUNT() FROM Error_Log__c];
    }

    private static Household_Member__c member(Account household, Contact person) {
        return new Household_Member__c(
            Household__c = household.Id,
            Contact__c = person.Id,
            Start_Date__c = Date.today()
        );
    }

    /** A household with one member, and that member's row deleted so a later write is refused. */
    private static List<Household_Member__c> memberships(Integer howMany, Boolean deleted) {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('Writer Household');
        insert household;
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            people.add(HouseholdTestDataFactory.newContact('Writer' + i, 'Person'));
        }
        insert people;
        List<Household_Member__c> rows = new List<Household_Member__c>();
        for (Contact person : people) {
            rows.add(member(household, person));
        }
        insert rows;
        if (deleted) {
            delete rows;
        }
        return rows;
    }

    @IsTest
    static void anEmptyListChangesNothing() {
        System.runAs(TestUsers.admin()) {
            Integer before = loggedErrors();

            Test.startTest();
            Assert.isTrue(HouseholdWriter.createHouseholds(null).isEmpty(), 'Create null');
            Assert.isTrue(
                HouseholdWriter.createHouseholds(new List<Account>()).isEmpty(),
                'Create empty'
            );
            Assert.isTrue(
                HouseholdWriter.updateHouseholdsReportingRefusals(null).isEmpty(),
                'Update null'
            );
            Assert.isTrue(
                HouseholdWriter.updateHouseholdsReportingRefusals(new List<Account>()).isEmpty(),
                'Update empty'
            );
            HouseholdWriter.updateHouseholds(null);
            HouseholdWriter.createMemberships(null);
            HouseholdWriter.createMemberships(new List<Household_Member__c>());
            Assert.isTrue(HouseholdWriter.linkContactsToHouseholds(null).isEmpty(), 'Link null');
            Assert.isTrue(
                HouseholdWriter.linkContactsToHouseholds(new List<Contact>()).isEmpty(),
                'Link empty'
            );
            HouseholdWriter.saveMergedMemberships(null, null);
            HouseholdWriter.saveMergedMemberships(
                new List<Household_Member__c>(),
                new List<Household_Member__c>()
            );
            HouseholdWriter.collapseMemberships(null, null);
            HouseholdWriter.collapseMemberships(
                new List<Household_Member__c>(),
                new List<Household_Member__c>()
            );
            HouseholdWriter.deleteHouseholds(null);
            HouseholdWriter.deleteHouseholds(new List<Account>());
            HouseholdWriter.deleteMemberships(null);
            HouseholdWriter.deleteMemberships(new List<Household_Member__c>());
            HouseholdWriter.undeleteMemberships(null);
            HouseholdWriter.undeleteMemberships(new List<Household_Member__c>());
            Test.stopTest();

            Assert.areEqual(before, loggedErrors(), 'Nothing was asked, so nothing was logged');
        }
    }

    @IsTest
    static void aRefusedHouseholdUpdateIsReportedByIdAndLogged() {
        System.runAs(TestUsers.admin()) {
            Account kept = HouseholdTestDataFactory.newHousehold('Kept Household');
            Account refused = HouseholdTestDataFactory.newHousehold('Refused Household');
            insert new List<Account>{ kept, refused };
            kept.Name = 'Kept Household Renamed';
            refused.Name = 'x'.repeat(Account.Name.getDescribe().getLength() + 1);
            Integer before = loggedErrors();

            Test.startTest();
            Set<Id> reported = HouseholdWriter.updateHouseholdsReportingRefusals(
                new List<Account>{ kept, refused }
            );
            Test.stopTest();

            Assert.areEqual(new Set<Id>{ refused.Id }, reported, 'Only the refused household');
            Assert.areEqual(
                'Kept Household Renamed',
                [SELECT Name FROM Account WHERE Id = :kept.Id].Name,
                'The others are still saved'
            );
            Assert.isTrue(loggedErrors() > before, 'The refusal is in the Error Log');
        }
    }

    @IsTest
    static void aRefusedHouseholdCreateIsReturnedAndLogged() {
        System.runAs(TestUsers.admin()) {
            HouseholdWriter.refuseCreatesForTest = true;
            Integer before = loggedErrors();

            Test.startTest();
            List<Database.SaveResult> saves = HouseholdWriter.createHouseholds(
                new List<Account>{ HouseholdTestDataFactory.newHousehold('Too Long') }
            );
            Test.stopTest();

            Assert.isFalse(saves[0].isSuccess(), 'The platform refused the name');
            Assert.areNotEqual('', HouseholdWriter.failureReason(saves[0]), 'With its reason');
            Assert.isTrue(loggedErrors() > before, 'The refusal is in the Error Log');
        }
    }

    @IsTest
    static void aSavedHouseholdHasNoFailureReason() {
        System.runAs(TestUsers.admin()) {
            List<Database.SaveResult> saves = HouseholdWriter.createHouseholds(
                new List<Account>{ HouseholdTestDataFactory.newHousehold('Fine Household') }
            );

            Assert.isTrue(saves[0].isSuccess(), 'Saved');
            Assert.areEqual('', HouseholdWriter.failureReason(saves[0]), 'No reason to give');
        }
    }

    @IsTest
    static void membershipsAndLinksAreWrittenAndRefusalsLogged() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('Link Household');
            insert household;
            Contact person = HouseholdTestDataFactory.newContact('Link', 'Person');
            insert person;
            Integer before = loggedErrors();

            Test.startTest();
            HouseholdWriter.createMemberships(
                new List<Household_Member__c>{
                    member(household, person),
                    new Household_Member__c(Start_Date__c = Date.today())
                }
            );
            List<Database.SaveResult> links = HouseholdWriter.linkContactsToHouseholds(
                new List<Contact>{ new Contact(Id = person.Id, LastName = '') }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c = :person.Id],
                'The valid membership is saved and the refused one is not'
            );
            Assert.isFalse(links[0].isSuccess(), 'A contact without a last name is refused');
            Assert.isTrue(loggedErrors() > before, 'Both refusals are in the Error Log');
        }
    }

    @IsTest
    static void aMergeSettleRefusalIsLoggedForEachSideOfTheCollapse() {
        System.runAs(TestUsers.admin()) {
            List<Household_Member__c> gone = memberships(2, true);
            Integer before = loggedErrors();

            Test.startTest();
            HouseholdWriter.collapseMemberships(
                new List<Household_Member__c>{ gone[0] },
                new List<Household_Member__c>{ gone[1] }
            );
            Test.stopTest();

            Assert.isTrue(
                loggedErrors() >= before + 2,
                'A refused update and a refused delete are each logged'
            );
        }
    }

    @IsTest
    static void aMergedMembershipThatCannotBeSavedFailsTheMerge() {
        System.runAs(TestUsers.admin()) {
            List<Household_Member__c> gone = memberships(1, true);
            Boolean failed = false;

            try {
                HouseholdWriter.saveMergedMemberships(
                    new List<Household_Member__c>(),
                    new List<Household_Member__c>{ gone[0] }
                );
            } catch (DmlException refused) {
                failed = true;
            }

            Assert.isTrue(failed, 'The merge settle step is all or nothing');
        }
    }

    @IsTest
    static void deletesAndRestoresAreLoggedNotThrown() {
        System.runAs(TestUsers.admin()) {
            List<Household_Member__c> rows = memberships(1, true);
            Account emptied = HouseholdTestDataFactory.newHousehold('Emptied Household');
            insert emptied;
            delete emptied;
            Integer before = loggedErrors();

            Test.startTest();
            HouseholdWriter.deleteHouseholds(new List<Account>{ emptied });
            HouseholdWriter.deleteMemberships(new List<Household_Member__c>{ rows[0] });
            HouseholdWriter.undeleteMemberships(
                new List<Household_Member__c>{ new Household_Member__c() }
            );
            Test.stopTest();

            Assert.isTrue(
                loggedErrors() >= before + 3,
                'A delete that finds nothing, and a restore of a row that was never deleted, are logged'
            );
        }
    }

    @IsTest
    static void aDeleteOrRestoreTheTransactionRejectsIsLoggedNotThrown() {
        System.runAs(TestUsers.admin()) {
            Integer before = loggedErrors();

            Test.startTest();
            HouseholdWriter.deleteHouseholds(new List<Account>{ new Account() });
            HouseholdWriter.deleteMemberships(
                new List<Household_Member__c>{ new Household_Member__c() }
            );
            HouseholdWriter.undeleteMemberships(
                new List<Household_Member__c>{ new Household_Member__c() }
            );
            Test.stopTest();

            Assert.isTrue(
                loggedErrors() >= before + 3,
                'Records without an id cannot be deleted or restored, and each is logged'
            );
        }
    }

    @IsTest
    static void membershipsAndHouseholdsAreDeletedAsTheRunningUser() {
        System.runAs(TestUsers.admin()) {
            List<Household_Member__c> rows = memberships(2, false);
            Account emptied = HouseholdTestDataFactory.newHousehold('Emptied Household');
            insert emptied;

            Test.startTest();
            HouseholdWriter.deleteMemberships(rows);
            HouseholdWriter.deleteHouseholds(new List<Account>{ emptied });
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Id IN :rows],
                'The memberships are gone'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :emptied.Id],
                'So is the emptied household'
            );
        }
    }
}
