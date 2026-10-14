/**
 * The Data Hygiene checks (C-28, canonical model R-SQ6): each one counted as the person in user
 * mode over the same document Find runs, with 200-record cases, the records each check must not
 * count, junction mode's count without a Find query, and a refusal shown in place of a number.
 *
 * Every test states its membership mode and an org shape, so none depends on Person Accounts;
 * the person account count is reached through a shape that names a record type as a person
 * type.
 */
@IsTest(testFor='ApexClass:DataHygieneService')
private class DataHygieneServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static void platformOnlyShape() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNativeHouseholdGroups = false;
        OrgShapeDetector.overrideShape = shape;
    }

    /** The mode, keeping empty households, so a test can leave one empty on purpose. */
    private static void mode(String membershipMode) {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(membershipMode);
        settings.Delete_Empty_Households__c = false;
        HouseholdTestDataFactory.save(settings);
        platformOnlyShape();
    }

    private static Account newOrganization(String name) {
        return new Account(
            Name = name,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    private static List<Contact> insertWithoutAutomaticHouseholds(List<Contact> contacts) {
        HouseholdService.suspendAutomaticCreation();
        insert contacts;
        HouseholdService.resumeAutomaticCreation();
        return contacts;
    }

    private static DataHygieneService.CheckResult runAs(User person, String key) {
        DataHygieneService.CheckResult result;
        System.runAs(person) {
            result = DataHygieneService.run(key);
        }
        return result;
    }

    /** What Find lists for the same document and the same person. */
    private static Integer findRows(User person, String key) {
        Integer rows;
        System.runAs(person) {
            rows = FindController.runQuery(DataHygieneService.queryDocument(key)).rows.size();
        }
        return rows;
    }

    @IsTest
    static void contactModeCountsTwoHundredPeopleWithNoHouseholdAndFindListsTheSame() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            Account organization = newOrganization('Acme Foundation');
            insert organization;
            Contact staff = HouseholdTestDataFactory.newContact('Sam', 'Staff');
            staff.AccountId = organization.Id;
            insert staff;
            insertWithoutAutomaticHouseholds(HouseholdTestDataFactory.manyContacts(200, 'Loose'));
            insert HouseholdTestDataFactory.newContact('Cy', 'Housed');
            User maria = maria();

            Test.startTest();
            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.PEOPLE_WITHOUT_HOUSEHOLD
            );
            Integer listed = findRows(maria, DataHygieneService.PEOPLE_WITHOUT_HOUSEHOLD);
            Test.stopTest();

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(200, result.count, 'Only the 200 with no account are counted.');
            Assert.areEqual('200', result.countLabel, 'The count is shown as a number.');
            Assert.isTrue(result.canOpenInFind, 'Contact mode opens in Find.');
            Assert.areEqual(200, listed, 'Find lists exactly what was counted.');
        }
    }

    @IsTest
    static void junctionModeCountsPeopleWithNoMembershipWithoutAFindQuery() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_JUNCTION);
            insertWithoutAutomaticHouseholds(HouseholdTestDataFactory.manyContacts(3, 'Loose'));
            insert HouseholdTestDataFactory.newContact('Cy', 'Housed');
            User maria = maria();

            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.PEOPLE_WITHOUT_HOUSEHOLD
            );

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(3, result.count, 'The three with no current membership.');
            Assert.isFalse(result.canOpenInFind, 'Find cannot ask about a missing membership yet.');
            Assert.areEqual(
                System.Label.Core_DataHygiene_NotInFindYet,
                result.note,
                'And says so.'
            );
            Assert.isNull(
                DataHygieneService.queryDocument(DataHygieneService.PEOPLE_WITHOUT_HOUSEHOLD),
                'There is no document to open.'
            );
        }
    }

    /**
     * People kept as accounts are counted too: the shape names a record type as a person type,
     * so its 200 accounts with no membership stand for 200 person accounts.
     */
    @IsTest
    static void junctionModeCountsPeopleKeptAsAccountsWithNoMembership() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_JUNCTION);
            List<Account> standIns = new List<Account>();
            for (Integer index = 0; index < 200; index++) {
                standIns.add(newOrganization('Stand-in ' + index));
            }
            insert standIns;
            OrgShapeDetector.overrideShape.personAccountRecordTypeIds = new Set<Id>{
                standIns[0].RecordTypeId
            };
            insertWithoutAutomaticHouseholds(HouseholdTestDataFactory.manyContacts(3, 'Loose'));

            DataHygieneService.CheckResult result = runAs(
                maria(),
                DataHygieneService.PEOPLE_WITHOUT_HOUSEHOLD
            );

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(203, result.count, 'Three contacts and 200 people kept as accounts.');
        }
    }

    @IsTest
    static void countsTwoHundredHouseholdsWithNobodyButNotOrganizationsOrLivedInHouseholds() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> accounts = new List<Account>();
            for (Integer index = 0; index < 200; index++) {
                Account empty = HouseholdTestDataFactory.newHousehold('Empty ' + index);
                // Half never counted (empty) and half counted to zero: both are empty.
                empty.Member_Count__c = Math.mod(index, 2) == 0 ? null : 0;
                accounts.add(empty);
            }
            Account lived = HouseholdTestDataFactory.newHousehold('The Lived Family');
            accounts.add(lived);
            accounts.add(newOrganization('Acme Foundation'));
            insert accounts;
            Contact member = HouseholdTestDataFactory.newContact('Dee', 'Lived');
            member.AccountId = lived.Id;
            insert member;
            User maria = maria();

            Test.startTest();
            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS
            );
            Integer listed = findRows(maria, DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS);
            Test.stopTest();

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(200, result.count, 'Only the empty households.');
            Assert.areEqual(200, listed, 'Find lists the same households.');
        }
    }

    @IsTest
    static void countsTwoHundredMembershipsThatNameNobody() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_JUNCTION);
            Account household = HouseholdTestDataFactory.newHousehold('The Kept Family');
            insert household;
            // A membership is saved naming a person (R-M4); it comes to name nobody when that
            // person is deleted with the household automation off, which is how it happens.
            List<Contact> gone = insertWithoutAutomaticHouseholds(
                HouseholdTestDataFactory.manyContacts(200, 'Gone')
            );
            List<Household_Member__c> rows = new List<Household_Member__c>();
            for (Contact goner : gone) {
                rows.add(
                    new Household_Member__c(Household__c = household.Id, Contact__c = goner.Id)
                );
            }
            Contact person = HouseholdTestDataFactory.newContact('Eve', 'Named');
            insertWithoutAutomaticHouseholds(new List<Contact>{ person });
            rows.add(new Household_Member__c(Household__c = household.Id, Contact__c = person.Id));
            insert rows;
            AutomationControl.bypass('ContactTriggerHandler');
            delete gone;
            AutomationControl.clearBypass('ContactTriggerHandler');
            User maria = maria();

            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.MEMBERSHIPS_WITHOUT_PERSON
            );

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(200, result.count, 'The row that names a person is not counted.');
        }
    }

    @IsTest
    static void countsTwoHundredAddressesWhoseOwnerWasDeleted() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            Account gone = newOrganization('Gone Ltd');
            Account kept = newOrganization('Kept Ltd');
            insert new List<Account>{ gone, kept };
            List<Address__c> addresses = new List<Address__c>();
            for (Integer index = 0; index < 200; index++) {
                addresses.add(
                    new Address__c(
                        Account__c = gone.Id,
                        Type__c = 'Other',
                        City__c = 'Town ' + index
                    )
                );
            }
            addresses.add(new Address__c(Account__c = kept.Id, Type__c = 'Work', City__c = 'Kept'));
            insert addresses;
            delete gone;
            User maria = maria();

            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.ADDRESSES_WITHOUT_OWNER
            );

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(
                200,
                result.count,
                'The address that still has an owner is not counted.'
            );
        }
    }

    @IsTest
    static void countsTwoHundredDefaultAddressesWithAPartMissingButNotOlderOnes() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> households = new List<Account>();
            for (Integer index = 0; index < 202; index++) {
                households.add(HouseholdTestDataFactory.newHousehold('Family ' + index));
            }
            insert households;
            List<Address__c> addresses = new List<Address__c>();
            for (Integer index = 0; index < 200; index++) {
                Address__c missing = new Address__c(
                    Account__c = households[index].Id,
                    Type__c = 'Home',
                    Is_Default__c = true,
                    Street__c = '1 Main St',
                    City__c = 'Springfield',
                    Postal_Code__c = '12345'
                );
                // Each part is the missing one in turn.
                Integer part = Math.mod(index, 3);
                if (part == 0) {
                    missing.Street__c = null;
                } else if (part == 1) {
                    missing.City__c = null;
                } else {
                    missing.Postal_Code__c = null;
                }
                addresses.add(missing);
            }
            addresses.add(
                new Address__c(
                    Account__c = households[200].Id,
                    Type__c = 'Home',
                    Is_Default__c = true,
                    Street__c = '2 Main St',
                    City__c = 'Springfield',
                    Postal_Code__c = '12345'
                )
            );
            addresses.add(
                new Address__c(
                    Account__c = households[201].Id,
                    Type__c = 'Other',
                    Is_Default__c = false,
                    City__c = 'History only'
                )
            );
            insert addresses;
            User maria = maria();

            Test.startTest();
            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.DEFAULT_ADDRESSES_INCOMPLETE
            );
            Integer listed = findRows(maria, DataHygieneService.DEFAULT_ADDRESSES_INCOMPLETE);
            Test.stopTest();

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(200, result.count, 'Only default addresses with a part missing.');
            Assert.areEqual(200, listed, 'Find lists the same addresses.');
        }
    }

    @IsTest
    static void countsDefaultAddressesThatFailedVerification() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            Account first = HouseholdTestDataFactory.newHousehold('First Family');
            Account second = HouseholdTestDataFactory.newHousehold('Second Family');
            insert new List<Account>{ first, second };
            insert new List<Address__c>{
                new Address__c(
                    Account__c = first.Id,
                    Type__c = 'Home',
                    Is_Default__c = true,
                    City__c = 'Springfield',
                    Verification_Status__c = 'Failed'
                ),
                new Address__c(
                    Account__c = second.Id,
                    Type__c = 'Other',
                    Is_Default__c = false,
                    City__c = 'Old',
                    Verification_Status__c = 'Failed'
                ),
                new Address__c(
                    Account__c = second.Id,
                    Type__c = 'Home',
                    Is_Default__c = true,
                    City__c = 'Springfield',
                    Verification_Status__c = 'Verified'
                )
            };
            User maria = maria();

            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.DEFAULT_ADDRESSES_FAILED
            );

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(1, result.count, 'Only the default address that failed.');
        }
    }

    @IsTest
    static void runAllListsEveryCheckInOrderAndShowsZeroWhenClean() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            User maria = maria();

            List<DataHygieneService.CheckResult> results;
            System.runAs(maria) {
                results = DataHygieneService.runAll();
            }

            Assert.areEqual(DataHygieneService.CHECK_KEYS.size(), results.size(), 'Every check.');
            for (Integer index = 0; index < results.size(); index++) {
                Assert.areEqual(
                    DataHygieneService.CHECK_KEYS[index],
                    results[index].key,
                    'In order.'
                );
                Assert.isNull(results[index].errorMessage, results[index].key + ' runs.');
                Assert.areEqual(0, results[index].count, results[index].key + ' finds nothing.');
                Assert.isFalse(String.isBlank(results[index].title), 'Each has a title.');
                Assert.isFalse(String.isBlank(results[index].description), 'And a description.');
            }
        }
    }

    @IsTest
    static void emptyHouseholdsWarnNotToDeleteWhenNonprofitCloudHouseholdsExist() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            User maria = maria();
            DataHygieneService.CheckResult platformOnly = runAs(
                maria,
                DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS
            );
            OrgShapeDetector.OrgShape nativeShape = new OrgShapeDetector.OrgShape();
            nativeShape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = nativeShape;

            Test.startTest();
            DataHygieneService.CheckResult withNative = runAs(
                maria,
                DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS
            );
            DataHygieneService.CheckResult otherCheck = runAs(
                maria,
                DataHygieneService.MEMBERSHIPS_WITHOUT_PERSON
            );
            Test.stopTest();

            Assert.isNull(platformOnly.note, 'No note where there are no native households.');
            Assert.areEqual(
                System.Label.Core_DataHygiene_NativeHouseholdsListed,
                withNative.note,
                'The empty households check warns not to delete a Nonprofit Cloud household.'
            );
            Assert.isTrue(withNative.canOpenInFind, 'It still opens in Find.');
            Assert.isNull(otherCheck.note, 'Only that check carries the warning.');
        }
    }

    @IsTest
    static void aCheckOnAnObjectThePersonCannotSeeSaysSoInsteadOfANumber() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            User david = TestDataFactory.createUser(
                'David',
                new List<String>{ 'BarnCRM_Find_And_Export' }
            );

            DataHygieneService.CheckResult result;
            Boolean canSeeAddresses;
            System.runAs(david) {
                canSeeAddresses = Schema.SObjectType.Address__c.isAccessible();
                result = DataHygieneService.run(DataHygieneService.ADDRESSES_WITHOUT_OWNER);
            }

            if (canSeeAddresses) {
                Assert.areEqual(0, result.count, 'Where the profile grants addresses, it counts.');
            } else {
                Assert.isNull(result.count, 'No number for what David cannot see.');
                Assert.isFalse(String.isBlank(result.errorMessage), 'The check says why instead.');
            }
        }
    }

    @IsTest
    static void pastTheCapTheCountSaysMoreThan() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                String.format(
                    System.Label.Core_DataHygiene_MoreThan,
                    new List<Object>{ DataHygieneService.COUNT_CAP.format() }
                ),
                DataHygieneService.countLabel(DataHygieneService.COUNT_CAP + 1),
                'More than the cap.'
            );
            Assert.areEqual(
                DataHygieneService.COUNT_CAP.format(),
                DataHygieneService.countLabel(DataHygieneService.COUNT_CAP),
                'The cap itself is a number.'
            );
        }
    }

    @IsTest
    static void everyDocumentIsAFindDocumentWithNoNamespaceWrittenIn() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            for (String key : DataHygieneService.CHECK_KEYS) {
                QueryCompiler.QueryDocument parsed = QueryCompiler.parse(
                    DataHygieneService.queryDocument(key)
                );
                Assert.isFalse(parsed.fields.isEmpty(), key + ' has columns.');
                Assert.areEqual('CreatedDate', parsed.orderField, key + ' lists oldest first.');
                Assert.isTrue(
                    DataHygieneService.savedQueryName(key).length() <= 80,
                    key + ' has a saved query name Find accepts.'
                );
            }
        }
    }

    @IsTest
    static void countsTwoHundredPeopleNobodyCanReachButNotTheReachableOrTheDeceased() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Silent');
            Contact emailed = HouseholdTestDataFactory.newContact('Em', 'Mailed');
            emailed.Email = 'em.mailed@example.org';
            Contact phoned = HouseholdTestDataFactory.newContact('Ph', 'Oned');
            phoned.MobilePhone = '555 0100';
            Contact posted = HouseholdTestDataFactory.newContact('Po', 'Sted');
            posted.MailingPostalCode = '02139';
            Contact deceased = HouseholdTestDataFactory.newContact('De', 'Ceased');
            deceased.Deceased__c = true;
            people.addAll(new List<Contact>{ emailed, phoned, posted, deceased });
            insertWithoutAutomaticHouseholds(people);
            User maria = maria();

            Test.startTest();
            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.PEOPLE_UNREACHABLE
            );
            Integer listed = findRows(maria, DataHygieneService.PEOPLE_UNREACHABLE);
            Test.stopTest();

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(200, result.count, 'Only the 200 with no way to reach them.');
            Assert.isTrue(result.canOpenInFind, 'It opens in Find.');
            Assert.areEqual(200, listed, 'Find lists exactly what was counted.');
        }
    }

    @IsTest
    static void countsTwoHundredDeceasedPeopleWhoCanStillBeEmailed() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Late');
            for (Integer index = 0; index < people.size(); index++) {
                people[index].Deceased__c = true;
                people[index].Email = 'late' + index + '@example.org';
            }
            Contact optedOut = HouseholdTestDataFactory.newContact('Op', 'Out');
            optedOut.Deceased__c = true;
            optedOut.Email = 'op.out@example.org';
            optedOut.HasOptedOutOfEmail = true;
            Contact living = HouseholdTestDataFactory.newContact('Li', 'Ving');
            living.Email = 'li.ving@example.org';
            people.addAll(new List<Contact>{ optedOut, living });
            insertWithoutAutomaticHouseholds(people);
            User maria = maria();

            Test.startTest();
            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.DECEASED_STILL_EMAILED
            );
            Integer listed = findRows(maria, DataHygieneService.DECEASED_STILL_EMAILED);
            Test.stopTest();

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(200, result.count, 'Not the opted out, not the living.');
            Assert.areEqual(200, listed, 'Find lists exactly what was counted.');
        }
    }

    @IsTest
    static void peopleNotChangedReadTheirYearsFromSettingsWithinBounds() {
        System.runAs(TestUsers.admin()) {
            mode(HouseholdTestDataFactory.MODE_CONTACT);
            Assert.areEqual(
                DataHygieneService.DEFAULT_STALE_YEARS,
                DataHygieneService.staleYears(),
                'Empty reads as the default.'
            );
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Stale_Record_Years__c = 50;
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(20, DataHygieneService.staleYears(), 'Above the maximum reads as 20.');
            settings.Stale_Record_Years__c = 0;
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(1, DataHygieneService.staleYears(), 'Below the minimum reads as 1.');
            settings.Stale_Record_Years__c = 3;
            HouseholdTestDataFactory.save(settings);
            insertWithoutAutomaticHouseholds(HouseholdTestDataFactory.manyContacts(200, 'Fresh'));
            User maria = maria();

            Test.startTest();
            DataHygieneService.CheckResult result = runAs(
                maria,
                DataHygieneService.PEOPLE_NOT_UPDATED
            );
            Test.stopTest();

            Assert.isNull(result.errorMessage, 'The check runs: ' + result.errorMessage);
            Assert.areEqual(0, result.count, 'People changed today are not listed.');
            Assert.isTrue(result.title.contains('3'), 'The title names the years: ' + result.title);
            Assert.isTrue(result.canOpenInFind, 'It opens in Find.');
        }
    }

    @IsTest
    static void anUnknownCheckIsRefused() {
        System.runAs(TestUsers.admin()) {
            try {
                DataHygieneService.queryDocument('no_such_check');
                Assert.fail('An unknown key is refused.');
            } catch (DataHygieneService.DataHygieneException refused) {
                Assert.areEqual(
                    System.Label.Core_DataHygiene_UnknownCheck,
                    refused.getMessage(),
                    'With a message.'
                );
            }
        }
    }
}
