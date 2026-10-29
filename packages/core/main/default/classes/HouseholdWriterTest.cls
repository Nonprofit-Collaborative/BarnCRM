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
        Database.insert(household, AccessLevel.SYSTEM_MODE);
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
            Database.insert(new List<Account>{ kept, refused }, AccessLevel.SYSTEM_MODE);
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
    static void householdsAreSavedPastDuplicateRulesOneRowAtATime() {
        System.runAs(TestUsers.admin()) {
            // A test cannot add a duplicate rule, so the options the writer saves with are read.
            Database.DMLOptions options = HouseholdWriter.householdSaveOptions();

            Assert.isTrue(
                options.DuplicateRuleHeader.allowSave,
                'A blocking Account duplicate rule cannot refuse a household, nor the person'
            );
            Assert.isFalse(options.optAllOrNone, 'One refused household never stops the rest');
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
            Database.insert(household, AccessLevel.SYSTEM_MODE);
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
            Database.insert(emptied, AccessLevel.SYSTEM_MODE);
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
            Database.insert(emptied, AccessLevel.SYSTEM_MODE);

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

    // ------------------------------------------------- households a person asks for

    /** A staff member whose access comes only from BarnCRM Staff, as in a real org. */
    private static User staff(String lastName) {
        return TestUsers.minimumAccessUserWith(lastName, new List<String>{ 'BarnCRM_Staff' });
    }

    private static String refusalFor(List<Account> households, Set<Id> touched) {
        try {
            HouseholdWriter.createHouseholdsForUser(households, touched);
        } catch (HouseholdException e) {
            return e.getMessage();
        }
        return null;
    }

    private static Integer householdsNamed(String name) {
        return [SELECT COUNT() FROM Account WHERE Name = :name WITH SYSTEM_MODE];
    }

    @IsTest
    static void aPersonWhoMayCreateAccountsGetsAHouseholdOfTheHouseholdRecordType() {
        System.runAs(TestUsers.admin()) {
            User maria = staff('Hwstaff');
            Account household = new Account(Name = 'Asked For Household', Member_Count__c = 0);
            List<Database.SaveResult> saves;

            Test.startTest();
            System.runAs(maria) {
                Assert.isTrue(HouseholdWriter.canCreateHouseholds(), 'Maria may create one');
                saves = HouseholdWriter.createHouseholdsForUser(
                    new List<Account>{ household },
                    new Set<Id>()
                );
            }
            Test.stopTest();

            Assert.isTrue(saves[0].isSuccess(), HouseholdWriter.failureReason(saves[0]));
            Assert.areEqual(
                HouseholdService.householdRecordTypeId(),
                [SELECT RecordTypeId FROM Account WHERE Id = :saves[0].getId()].RecordTypeId,
                'A record with no record type is given Household'
            );
        }
    }

    @IsTest
    static void aPersonWhoCannotCreateAccountsIsRefusedAndNothingIsCreated() {
        System.runAs(TestUsers.admin()) {
            User reader = TestUsers.peopleReaderWith('Hwreader', new List<String>());
            String message;

            Test.startTest();
            System.runAs(reader) {
                Assert.isFalse(HouseholdWriter.canCreateHouseholds(), 'No button for a reader');
                message = refusalFor(
                    new List<Account>{ HouseholdTestDataFactory.newHousehold('Reader Household') },
                    null
                );
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Households_ErrorCreateNoAccess, message, 'Refused');
            Assert.areEqual(0, householdsNamed('Reader Household'), 'Nothing was created');
        }
    }

    @IsTest
    static void aFieldThePersonCannotSetIsRefusedAndNothingIsCreated() {
        System.runAs(TestUsers.admin()) {
            User maria = staff('Hwfield');
            Account household = HouseholdTestDataFactory.newHousehold('Field Household');
            // Sample Data is the package's own marker, which BarnCRM Staff cannot edit.
            household.Sample_Data__c = true;
            String message;

            Test.startTest();
            System.runAs(maria) {
                message = refusalFor(new List<Account>{ household }, null);
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Households_ErrorCreateNoAccess, message, 'Refused');
            Assert.areEqual(0, householdsNamed('Field Household'), 'Nothing was created');
        }
    }

    @IsTest
    static void aTouchedHouseholdThePersonCannotEditIsRefusedAndNothingIsCreated() {
        System.runAs(TestUsers.admin()) {
            String orgDefault = [SELECT DefaultAccountAccess FROM Organization LIMIT 1]
            .DefaultAccountAccess;
            if (orgDefault == 'Edit' || orgDefault == 'ReadEditTransfer') {
                // Everyone edits every account here, so no household is one staff cannot edit.
                Assert.isNotNull(orgDefault, 'Only a public read and write org skips this');
                return;
            }
            Account theirs = HouseholdTestDataFactory.newHousehold('Not Theirs');
            Database.insert(theirs, AccessLevel.SYSTEM_MODE);
            User maria = staff('Hwtouch');
            String message;

            Test.startTest();
            System.runAs(maria) {
                message = refusalFor(
                    new List<Account>{ HouseholdTestDataFactory.newHousehold('Split Household') },
                    new Set<Id>{ theirs.Id }
                );
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Households_ErrorCreateNoHouseholdAccess, message, 'Refused');
            Assert.areEqual(0, householdsNamed('Split Household'), 'Nothing was created');
        }
    }

    @IsTest
    static void anAccountOfAnotherRecordTypeIsRefused() {
        System.runAs(TestUsers.admin()) {
            Id other;
            for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
                if (
                    !info.isMaster() &&
                    info.getRecordTypeId() != HouseholdService.householdRecordTypeId()
                ) {
                    other = info.getRecordTypeId();
                    break;
                }
            }
            if (other == null) {
                Assert.isNotNull(HouseholdService.householdRecordTypeId(), 'Only Household here');
                return;
            }
            User maria = staff('Hwother');
            String message;

            Test.startTest();
            System.runAs(maria) {
                message = refusalFor(
                    new List<Account>{ new Account(Name = 'Other Type', RecordTypeId = other) },
                    null
                );
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Households_ErrorNotAHousehold, message, 'Refused');
            Assert.areEqual(0, householdsNamed('Other Type'), 'Nothing was created');
        }
    }

    /** 251 households, then one more whose change touches all 251 (checked 200 at a time). */
    @IsTest
    static void twoHundredFiftyOneHouseholdsAreCreatedAndCheckedInBulk() {
        System.runAs(TestUsers.admin()) {
            User maria = staff('Hwbulk');
            List<Account> created;
            List<Database.SaveResult> last;

            Test.startTest();
            System.runAs(maria) {
                created = HouseholdTestDataFactory.insertHouseholds('Bulk Household', 251);
                Set<Id> touched = new Map<Id, Account>(created).keySet();
                last = HouseholdWriter.createHouseholdsForUser(
                    new List<Account>{ HouseholdTestDataFactory.newHousehold('Bulk Touching') },
                    touched
                );
            }
            Test.stopTest();

            Assert.isTrue(last[0].isSuccess(), HouseholdWriter.failureReason(last[0]));
            Id householdType = HouseholdService.householdRecordTypeId();
            Assert.areEqual(
                252,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE Name LIKE 'Bulk %' AND RecordTypeId = :householdType
                    WITH SYSTEM_MODE
                ],
                'Every household was created'
            );
        }
    }
}
