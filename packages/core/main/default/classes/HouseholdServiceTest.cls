/**
 * Membership in both modes: creation, counting, moving, and tidying up.
 * Canonical model R-H1, R-H2, R-H3, R-H11, R-H12.
 */
@IsTest(critical=true)
private class HouseholdServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void aNewPersonWithNoHouseholdGetsOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Test.stopTest();

            Contact saved = [
                SELECT AccountId, Account.Name, Account.Member_Count__c
                FROM Contact
                WHERE Id = :maria.Id
            ];
            Assert.isNotNull(saved.AccountId, 'Maria was given a household');
            Assert.areEqual(
                'The Garcia Family',
                saved.Account.Name,
                'The household is named from her surname'
            );
            Assert.areEqual(1, saved.Account.Member_Count__c, 'The household counts one member');
        }
    }

    @IsTest
    static void twoHundredPeopleInOneSaveEachGetAHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');

            Test.startTest();
            insert people;
            Test.stopTest();

            Integer withHousehold = [
                SELECT COUNT()
                FROM Contact
                WHERE Id IN :people AND AccountId != NULL
            ];
            Assert.areEqual(200, withHousehold, 'Every person in the batch has a household');
        }
    }

    /**
     * The defect ADR-0037 closes, asserted from the configuration an administrator arrives
     * at by following the product's own recommendation in a Nonprofit Cloud org: junction
     * membership, and nothing else changed.
     */
    @IsTest
    static void aNewPersonInJunctionModeGetsAHouseholdAndAMembershipRow() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);

            Test.startTest();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Test.stopTest();

            List<Household_Member__c> memberships = [
                SELECT
                    Household__c,
                    Contact__c,
                    Account__c,
                    Role__c,
                    Is_Primary__c,
                    Household__r.Name,
                    Household__r.Member_Count__c,
                    Household__r.RecordTypeId
                FROM Household_Member__c
                WHERE Contact__c = :maria.Id
            ];
            Assert.areEqual(1, memberships.size(), 'Maria was joined to a household (R-H2)');
            Assert.areEqual(
                HouseholdService.householdRecordTypeId(),
                memberships[0].Household__r.RecordTypeId,
                'The household is a household'
            );
            Assert.areEqual(
                'The Garcia Family',
                memberships[0].Household__r.Name,
                'And it is named from her surname, the same way contact mode names it'
            );
            Assert.areEqual(1, memberships[0].Household__r.Member_Count__c, 'And counts her');
            Assert.areEqual('Head', memberships[0].Role__c, 'She heads her own household');
            Assert.isTrue(memberships[0].Is_Primary__c, 'And is its primary member');
            Assert.isNull(
                memberships[0].Account__c,
                'She is recorded as a contact, because that is the object she is stored on'
            );
            Assert.areEqual(
                memberships[0].Household__c,
                HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id }).get(maria.Id),
                'And the service answers with that household when asked whose she is'
            );
        }
    }

    @IsTest
    static void noHouseholdIsCreatedInJunctionModeWhenTheSettingIsOff() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();

            Test.startTest();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'The org said no, so nobody was joined to anything'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ],
                'And no household was made either'
            );
        }
    }

    @IsTest
    static void twoHundredPeopleInOneSaveEachGetAHouseholdInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');

            Test.startTest();
            insert people;
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c IN :people],
                'Every person in the batch is joined to a household of their own (R-H2)'
            );
            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ],
                'And exactly one household was made for each of them, not two'
            );
        }
    }

    /**
     * Somebody saved straight into a household they were given is not given a second one.
     * This is how a person arrives from the merge and split screens and from an import that
     * names their household, and it is the junction mode form of the contact mode test that
     * a contact arriving with an account keeps it.
     */
    @IsTest
    static void aPersonSavedIntoAHouseholdInJunctionModeIsNotGivenASecondOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;

            Test.startTest();
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            john.AccountId = household.Id;
            insert john;
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ],
                'The household he was saved into is the only one there is'
            );
        }
    }

    /**
     * PEOPLE-10. A contact saved in junction mode with its account set to a household joins
     * that household with exactly one membership row, and is counted there.
     */
    @IsTest
    static void aPersonSavedIntoAHouseholdInJunctionModeJoinsItOnce() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;

            Test.startTest();
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            john.AccountId = household.Id;
            insert john;
            Test.stopTest();

            List<Household_Member__c> memberships = [
                SELECT Household__c, Is_Primary__c
                FROM Household_Member__c
                WHERE Contact__c = :john.Id AND End_Date__c = NULL
            ];
            Assert.areEqual(1, memberships.size(), 'John has one membership row');
            Assert.areEqual(
                household.Id,
                memberships[0].Household__c,
                'It is in the household his record names'
            );
            Assert.isFalse(
                memberships[0].Is_Primary__c,
                'He joins as an ordinary member: who is primary stays a decision (R-H10)'
            );
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :household.Id].Member_Count__c,
                'The household counts him'
            );
        }
    }

    /**
     * PEOPLE-10. In junction mode a contact's account can be an employer: no membership is
     * made in an organization, and the person still gets a household of their own.
     */
    @IsTest
    static void aPersonSavedAgainstAnOrganizationInJunctionModeDoesNotJoinIt() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account employer = new Account(Name = 'Riverside Library');
            insert employer;

            Test.startTest();
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            john.AccountId = employer.Id;
            insert john;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Household__c = :employer.Id],
                'The employer has no membership rows'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c = :john.Id],
                'John has the one membership of the household made for him'
            );
        }
    }

    /**
     * PEOPLE-10, bulk: two hundred contacts saved into one household in one save each join
     * it once.
     */
    @IsTest
    static void twoHundredPeopleSavedIntoAHouseholdInJunctionModeEachJoinItOnce() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account household = HouseholdTestDataFactory.newHousehold('The Bulk Family');
            insert household;
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');
            for (Contact person : people) {
                person.AccountId = household.Id;
            }

            Test.startTest();
            insert people;
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Household_Member__c WHERE Household__c = :household.Id],
                'One row each'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ],
                'Nobody was given a household of their own'
            );
        }
    }

    /**
     * PEOPLE-27. In contact mode the person a household is created for becomes its Primary
     * Contact, as junction mode marks them the primary member.
     */
    @IsTest
    static void aHouseholdCreatedForAPersonInContactModeNamesThemPrimaryContact() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Test.stopTest();

            Contact saved = [
                SELECT AccountId, Account.Primary_Contact__c
                FROM Contact
                WHERE Id = :maria.Id
            ];
            Assert.areEqual(
                maria.Id,
                saved.Account.Primary_Contact__c,
                'Maria is the Primary Contact of the household made for her'
            );
        }
    }

    /**
     * PEOPLE-27. In contact mode a household's Primary Contact must be one of its members:
     * somebody from another household is refused on save, with a message saying why.
     */
    @IsTest
    static void aPrimaryContactFromAnotherHouseholdIsRefusedInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account smiths = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Account garcias = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ smiths, garcias };
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            maria.AccountId = garcias.Id;
            insert maria;

            Test.startTest();
            Database.SaveResult result = Database.update(
                new Account(Id = smiths.Id, Primary_Contact__c = maria.Id),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'The save is refused');
            Assert.areEqual(
                Label.Core_Households_PrimaryContactMustBeMember,
                result.getErrors()[0].getMessage(),
                'The refusal says the Primary Contact has to be a member'
            );
        }
    }

    /**
     * PEOPLE-27. A new household cannot be created already naming a Primary Contact in
     * contact mode, because nobody can be its member yet.
     */
    @IsTest
    static void aNewHouseholdNamingAPrimaryContactIsRefusedInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Account household = HouseholdTestDataFactory.newHousehold('The Other Family');
            household.Primary_Contact__c = maria.Id;

            Test.startTest();
            Database.SaveResult result = Database.insert(household, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'The new household is refused');
        }
    }

    /**
     * PEOPLE-27. Clearing the Primary Contact, or saving a household whose primary has since
     * left, is never blocked.
     */
    @IsTest
    static void clearingThePrimaryContactIsAllowedInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

            Test.startTest();
            update new Account(Id = householdId, Primary_Contact__c = null);
            update new Account(Id = householdId, Name = 'Renamed');
            Test.stopTest();

            Assert.isNull(
                [SELECT Primary_Contact__c FROM Account WHERE Id = :householdId].Primary_Contact__c,
                'The Primary Contact was cleared'
            );
        }
    }

    /**
     * R-C1: every person gets a household. A household the platform refuses (a validation
     * rule, a required field, here a name too long for the field) must not leave the
     * person saved with none and nobody told: the person's own save fails, with the
     * reason, where a data loader or a screen shows any other failed row.
     */
    @IsTest
    static void aPersonWhoseHouseholdCannotBeCreatedIsNotSavedWithoutOne() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Household_Name_Pattern__c = 'Z'.repeat(240) + ' {LastName}';
            HouseholdTestDataFactory.save(settings);
            Contact maria = HouseholdTestDataFactory.newContact(
                'Ms.',
                'Maria',
                'Garcia' + 'x'.repeat(40)
            );

            String message;
            Test.startTest();
            try {
                insert maria;
            } catch (DmlException e) {
                message = e.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.isNotNull(
                message,
                'The save of the person fails rather than quietly succeeding'
            );
            Assert.isTrue(
                message.startsWith(
                    Label.Core_Households_ErrorCreateFailedForPerson.substringBefore('{0}')
                ),
                'The failure says the household could not be created: ' + message
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE FirstName = 'Maria'],
                'Nobody was saved without a household'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :Label.Core_Households_ErrorContextMembership
                ],
                'The administrator still finds the refusal in the Error Log'
            );
        }
    }

    /**
     * The same in junction mode, where the household is made after the person is saved
     * and the failure has to reach back to the person's own row.
     */
    @IsTest
    static void aPersonWhoseHouseholdCannotBeCreatedIsNotSavedWithoutOneInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            settings.Household_Name_Pattern__c = 'Z'.repeat(240) + ' {LastName}';
            HouseholdTestDataFactory.save(settings);
            Contact maria = HouseholdTestDataFactory.newContact(
                'Ms.',
                'Maria',
                'Garcia' + 'x'.repeat(40)
            );

            String message;
            Test.startTest();
            try {
                insert maria;
            } catch (DmlException e) {
                message = e.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.isNotNull(
                message,
                'The save of the person fails rather than quietly succeeding'
            );
            Assert.isTrue(
                message.startsWith(
                    Label.Core_Households_ErrorCreateFailedForPerson.substringBefore('{0}')
                ),
                'The failure says the household could not be created: ' + message
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE FirstName = 'Maria'],
                'Nobody was saved without a household'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'No membership row was left pointing at a household that does not exist'
            );
        }
    }

    @IsTest
    static void noHouseholdIsCreatedWhenTheSettingIsOff() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            HouseholdTestDataFactory.save(settings);

            Test.startTest();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Test.stopTest();

            Contact saved = [SELECT AccountId FROM Contact WHERE Id = :maria.Id];
            Assert.isNull(saved.AccountId, 'Nothing was created for Maria');
        }
    }

    @IsTest
    static void movingSomeoneRecountsBothHouseholdsAndDeletesTheEmptyOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

            Test.startTest();
            HouseholdService.moveContact(maria.Id, toHousehold);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :toHousehold].Member_Count__c,
                'The household Maria joined counts two'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
                'The household Maria left was empty and was deleted'
            );
        }
    }

    @IsTest
    static void anEmptyHouseholdIsKeptWhenTheSettingIsOff() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

            Test.startTest();
            HouseholdService.moveContact(maria.Id, toHousehold);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
                'The empty household was kept because the org asked for that'
            );
            Assert.areEqual(
                0,
                [SELECT Member_Count__c FROM Account WHERE Id = :fromHousehold].Member_Count__c,
                'The empty household counts nobody'
            );
        }
    }

    @IsTest
    static void junctionModeReadsMembersFromTheJunction() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = john.Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            Map<Id, List<HouseholdService.Person>> members = HouseholdService.getMembers(
                new Set<Id>{ household.Id }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                members.get(household.Id).size(),
                'The junction row is the membership'
            );
            Assert.areEqual(
                'Head',
                members.get(household.Id)[0].role,
                'The role comes from the junction row'
            );
            Assert.isTrue(
                members.get(household.Id)[0].isPrimary,
                'The primary flag comes from the junction row'
            );
        }
    }

    @IsTest
    static void junctionModeEndsTheOldMembershipWhenSomeoneMoves() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            // The household John leaves has to still be there afterwards for this test to be
            // able to look at what happened to his membership of it. Household Member cascades
            // from its household, so tidying the emptied household away would take the ended
            // membership row with it and there would be nothing left to assert on.
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Smith Family'),
                HouseholdTestDataFactory.newHousehold('The Garcia Family')
            };
            insert households;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            insert new Household_Member__c(
                Household__c = households[0].Id,
                Contact__c = john.Id,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            HouseholdService.moveContact(john.Id, households[1].Id);
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Contact__c = :john.Id AND End_Date__c != NULL
                ],
                'The old membership was ended rather than deleted'
            );
            Assert.areEqual(
                1,
                HouseholdService.getMembers(new Set<Id>{ households[1].Id })
                    .get(households[1].Id)
                    .size(),
                'John belongs to the household he moved to'
            );
            Assert.areEqual(
                0,
                HouseholdService.getMembers(new Set<Id>{ households[0].Id })
                    .get(households[0].Id)
                    .size(),
                'A membership ended today is over today, not tomorrow'
            );
            HouseholdService.recalculateMemberCounts(
                new Set<Id>{ households[0].Id, households[1].Id }
            );
            Assert.areEqual(
                0,
                [SELECT Member_Count__c FROM Account WHERE Id = :households[0].Id].Member_Count__c,
                'The household John left counts nobody'
            );
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :households[1].Id].Member_Count__c,
                'The household John joined counts him'
            );
            Assert.areEqual(
                households[1].Id,
                HouseholdService.getHouseholdIdsFor(new Set<Id>{ john.Id }).get(john.Id),
                'The household a caller is told about is the one he moved to'
            );
        }
    }

    @IsTest
    static void movingSomeoneNowhereIsRefusedWithAnExplanation() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            String message = '';
            try {
                HouseholdService.moveContact(null, null);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Assert.areEqual(
                Label.Core_Households_ErrorMoveMissingInput,
                message,
                'Maria is told what to do'
            );
        }
    }

    @IsTest
    static void movingSomeoneToAnOrganizationIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Account organization = new Account(Name = 'Riverside Community Trust');
            insert organization;
            String message = '';

            Test.startTest();
            try {
                HouseholdService.moveContact(maria.Id, organization.Id);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_ErrorNotAHousehold,
                message,
                'An organization is not a household'
            );
        }
    }

    @IsTest
    static void anOrgWithoutPeopleStoredAsAccountsSkipsThatBranch() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = false;

            Test.startTest();
            insert new Account(Name = 'Riverside Community Trust');
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'No membership was created'
            );
        }
    }

    @IsTest
    static void aPersonStoredAsAnAccountGetsAHouseholdAndAMembership() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = true;
            Account person = new Account(Name = 'Maria Garcia');
            insert person;

            Test.startTest();
            HouseholdService.createHouseholdsForPersonAccounts(new List<SObject>{ person });
            Test.stopTest();

            List<Household_Member__c> memberships = [
                SELECT Household__c, Account__c, Role__c, Is_Primary__c
                FROM Household_Member__c
                WHERE Account__c = :person.Id
            ];
            Assert.areEqual(1, memberships.size(), 'The person was joined to a household');
            Assert.areEqual(
                'Head',
                memberships[0].Role__c,
                'They are the head of their own household'
            );
            Assert.isTrue(memberships[0].Is_Primary__c, 'They are the primary member');
            Assert.isNotNull(memberships[0].Household__c, 'A household was created for them');
        }
    }

    @IsTest
    static void memberCountsAreRecalculatedForEveryHouseholdGiven() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            insert new List<Contact>{
                new Contact(
                    Salutation = 'Mr.',
                    FirstName = 'John',
                    LastName = 'Smith',
                    AccountId = household.Id
                ),
                new Contact(
                    Salutation = 'Mrs.',
                    FirstName = 'Jane',
                    LastName = 'Smith',
                    AccountId = household.Id
                )
            };
            update new Account(Id = household.Id, Member_Count__c = 99);

            Test.startTest();
            HouseholdService.recalculateMemberCounts(new Set<Id>{ household.Id });
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :household.Id].Member_Count__c,
                'The count was put right'
            );
        }
    }

    @IsTest
    static void theHouseholdOfAPersonIsAnsweredInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Contact atWork = HouseholdTestDataFactory.newContact('Mr.', 'Tom', 'Rivera');
            Account organization = new Account(Name = 'Riverside Community Trust');
            insert organization;
            atWork.AccountId = organization.Id;
            insert atWork;

            Test.startTest();
            Map<Id, Id> households = HouseholdService.getHouseholdIdsFor(
                new Set<Id>{ maria.Id, atWork.Id }
            );
            Test.stopTest();

            Assert.areEqual(household, households.get(maria.Id), 'Maria belongs to her household');
            Assert.areEqual(
                null,
                households.get(atWork.Id),
                'A person attached to an organization has no household'
            );
        }
    }

    @IsTest
    static void theHouseholdOfAPersonIsAnsweredInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Smith Family'),
                HouseholdTestDataFactory.newHousehold('The Garcia Family')
            };
            insert households;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert new List<Contact>{ john, maria };
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Contact__c = john.Id,
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = households[1].Id,
                    Contact__c = john.Id,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = households[1].Id,
                    Contact__c = maria.Id,
                    Start_Date__c = Date.today()
                )
            };

            Test.startTest();
            Map<Id, Id> answered = HouseholdService.getHouseholdIdsFor(
                new Set<Id>{ john.Id, maria.Id }
            );
            Test.stopTest();

            Assert.areEqual(
                households[0].Id,
                answered.get(john.Id),
                'John belongs to two households, so the one he is primary in is the answer'
            );
            Assert.areEqual(
                households[1].Id,
                answered.get(maria.Id),
                'Maria belongs to one household, so that is the answer'
            );
        }
    }

    /**
     * PEOPLE-12, R-M3. A person in two households and primary in neither is answered with
     * the membership that started first, whatever order the rows were saved in.
     */
    @IsTest
    static void withNoPrimaryTheEarliestCurrentMembershipIsThePersonsHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Smith Family'),
                HouseholdTestDataFactory.newHousehold('The Garcia Family')
            };
            insert households;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Contact__c = john.Id,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = households[1].Id,
                    Contact__c = john.Id,
                    Start_Date__c = Date.today().addYears(-3)
                )
            };

            Test.startTest();
            Id answered = HouseholdService.getHouseholdIdsFor(new Set<Id>{ john.Id }).get(john.Id);
            Test.stopTest();

            Assert.areEqual(
                households[1].Id,
                answered,
                'The household he joined three years ago is his household'
            );
        }
    }

    /**
     * PEOPLE-12, R-M3. Primary wins over an earlier start date.
     */
    @IsTest
    static void thePrimaryMembershipWinsOverAnEarlierOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Smith Family'),
                HouseholdTestDataFactory.newHousehold('The Garcia Family')
            };
            insert households;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Contact__c = john.Id,
                    Start_Date__c = Date.today().addYears(-3)
                ),
                new Household_Member__c(
                    Household__c = households[1].Id,
                    Contact__c = john.Id,
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                )
            };

            Test.startTest();
            Id answered = HouseholdService.getHouseholdIdsFor(new Set<Id>{ john.Id }).get(john.Id);
            Test.stopTest();

            Assert.areEqual(
                households[1].Id,
                answered,
                'The household he is primary in is his household'
            );
        }
    }

    @IsTest
    static void askingTwiceAsksTheDatabaseOnce() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;

            Test.startTest();
            HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id });
            Integer afterFirst = Limits.getQueries();
            HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id });
            Integer afterSecond = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(
                afterFirst,
                afterSecond,
                'The second question was answered from memory'
            );
        }
    }

    @IsTest
    static void theMembersOfAHouseholdAreAnsweredInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            Contact john = new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );
            insert john;

            Test.startTest();
            Map<Id, Set<Id>> members = HouseholdService.getMemberPersonIds(
                new Set<Id>{ household.Id }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                members.get(household.Id).size(),
                'One person belongs to the household'
            );
            Assert.isTrue(members.get(household.Id).contains(john.Id), 'That person is John');
        }
    }

    @IsTest
    static void theMembersOfAHouseholdAreAnsweredInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = john.Id,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            Map<Id, Set<Id>> members = HouseholdService.getMemberPersonIds(
                new Set<Id>{ household.Id }
            );
            Test.stopTest();

            Assert.isTrue(
                members.get(household.Id).contains(john.Id),
                'The junction row is the member'
            );
        }
    }

    @IsTest
    static void askingAboutNobodyAnswersNothing() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Assert.areEqual(
                0,
                HouseholdService.getHouseholdIdsFor(new Set<Id>()).size(),
                'No people asked about, nothing answered'
            );
            Assert.areEqual(
                0,
                HouseholdService.getMemberPersonIds(null).size(),
                'No households asked about, nothing answered'
            );
        }
    }

    @IsTest
    static void aPersonStoredAsAnAccountIsMovedThroughTheJunction() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            HouseholdService.personAccountOverride = true;
            PersonRecordSelector.personRecordOverride = true;
            Account person = new Account(Name = 'Maria Garcia');
            insert person;
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Garcia Family'),
                HouseholdTestDataFactory.newHousehold('The Lee Family')
            };
            insert households;
            insert new Household_Member__c(
                Household__c = households[0].Id,
                Account__c = person.Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            HouseholdService.moveContact(person.Id, households[1].Id);
            Test.stopTest();

            List<Household_Member__c> current = [
                SELECT Household__c, Account__c, Contact__c, Role__c, Is_Primary__c
                FROM Household_Member__c
                WHERE Account__c = :person.Id AND End_Date__c = NULL
            ];
            Assert.areEqual(1, current.size(), 'Maria has one current membership');
            Assert.areEqual(
                households[1].Id,
                current[0].Household__c,
                'It is the household she moved to'
            );
            Assert.areEqual(null, current[0].Contact__c, 'She is not recorded as a contact');
            Assert.areEqual('Head', current[0].Role__c, 'Her role came with her');
            Assert.isTrue(current[0].Is_Primary__c, 'So did the primary flag');
        }
    }

    @IsTest
    static void aPersonStoredAsAnAccountCannotBeMovedInTheSimpleMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            HouseholdService.personAccountOverride = true;
            PersonRecordSelector.personRecordOverride = true;
            Account person = new Account(Name = 'Maria Garcia');
            insert person;
            Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert household;
            String message = '';

            Test.startTest();
            try {
                HouseholdService.moveContact(person.Id, household.Id);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_ErrorMoveNeedsJunction,
                message,
                'Maria is told which setting has to change first'
            );
        }
    }

    @IsTest
    static void anOrganizationNeverGetsAMemberCount() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account organization = new Account(Name = 'Riverside Community Trust');
            insert organization;
            insert new Contact(
                Salutation = 'Mr.',
                FirstName = 'Tom',
                LastName = 'Rivera',
                AccountId = organization.Id
            );

            Test.startTest();
            HouseholdService.recalculateMemberCounts(new Set<Id>{ organization.Id });
            Test.stopTest();

            Assert.areEqual(
                null,
                [SELECT Member_Count__c FROM Account WHERE Id = :organization.Id].Member_Count__c,
                'A member count is never stamped on an organization'
            );
        }
    }

    @IsTest
    static void aStandardUserWithNoPackagedAccessCanStillSaveAPerson() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            User staff = HouseholdTestDataFactory.standardUser('house');

            Test.startTest();
            System.runAs(staff) {
                insert HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            }
            Test.stopTest();

            Contact saved = [
                SELECT AccountId, Account.Name, Account.Member_Count__c
                FROM Contact
                WHERE LastName = 'Garcia'
                LIMIT 1
            ];
            Assert.isNotNull(
                saved.AccountId,
                'The household was created for a user with no packaged access'
            );
            Assert.areEqual('The Garcia Family', saved.Account.Name, 'And it was named');
            Assert.areEqual(1, saved.Account.Member_Count__c, 'And counted');
        }
    }
    @IsTest
    static void upkeepAfterAMembershipChangeIsOnePlaceAnyCallerCanUse() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            insert household;
            // Saved without the trigger noticing, the way another package would leave it.
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            john.AccountId = household.Id;
            insert john;
            update new Account(Id = household.Id, Name = 'Placeholder', Member_Count__c = 0);

            Test.startTest();
            HouseholdService.afterMembershipChange(new Set<Id>{ household.Id });
            Test.stopTest();

            Account saved = [SELECT Name, Member_Count__c FROM Account WHERE Id = :household.Id];
            Assert.areEqual(1, saved.Member_Count__c, 'The household counts John again');
            Assert.areEqual('The Smith Family', saved.Name, 'And is named from him');
        }
    }
    @IsTest
    static void aScreenNeverShowsAFieldTheUserCannotRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            User staff = HouseholdTestDataFactory.standardUser('fls');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            // Saved by the same user who will read it back, so that what this test measures is
            // field level access and nothing else. Whether a user can see a person somebody
            // else entered is the org's sharing model, which differs from org to org, and a
            // test that depends on it is testing the org rather than the package.
            System.runAs(staff) {
                insert john;
            }
            // Marked deceased afterwards, by the administrator: this user cannot edit the field,
            // which is the point, so his own save cannot carry it.
            update new Contact(Id = john.Id, Deceased__c = true);
            Id householdId = [SELECT AccountId FROM Contact WHERE Id = :john.Id].AccountId;
            Assert.isTrue(
                HouseholdService.getMembers(new Set<Id>{ householdId }).get(householdId)[0]
                    .isDeceased,
                'Upkeep sees the whole record, which is how the greetings stay right'
            );

            List<HouseholdController.MemberView> shown;
            Test.startTest();
            System.runAs(staff) {
                shown = HouseholdController.getMembers(householdId);
            }
            Test.stopTest();

            Assert.areEqual(1, shown.size(), 'The panel still lists John');
            Assert.areEqual('John Smith', shown[0].name, 'By the name this user can read');
            Assert.isFalse(
                shown[0].isDeceased,
                'A user with no access to the deceased field is not told that he died'
            );
        }
    }

    /**
     * The junction mode counterpart of the contact save above, with the member stored as an
     * account rather than as a contact. Upkeep reads that person through
     * PersonRecordSelector, and a user mode read there fails on the packaged fields the
     * query selects, which fails the user's own save.
     *
     * What this test substitutes and what it does not: the org shape is declared through
     * personAccountOverride, because a Platform only test org has no person accounts to
     * make. Nothing else is substituted. PersonRecordSelector.personRecordOverride and
     * personOverridesByName are both left unset, so the query really runs, really selects
     * Deceased__c and Household_Role__c on Account, and the person really is built from
     * what came back. This test therefore measures the product and not the override.
     *
     * The user is given create access to the membership row and nothing else. The platform
     * checks the user's own access on the save itself, so a user who may not create a
     * membership at all is refused by the platform, correctly, before any upkeep runs. What
     * this test holds the product to is that upkeep never adds a refusal of its own: no
     * access to the packaged fields on Account is granted.
     */
    @IsTest
    static void aStandardUserWithNoPackagedAccessCanStillSaveAJunctionMembership() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = true;
            User staff = HouseholdTestDataFactory.standardUser('junc');
            HouseholdTestDataFactory.grantMembershipCreate('C01_Junction_Save_Test', staff.Id);
            // The household and the person are made by an administrator: a record type and a
            // packaged field are not what this test is about, and the save it measures is the
            // membership row. Both are handed to the user: a membership points at them, and
            // whether a user may point at an account somebody else owns is the org's sharing
            // model, which differs from org to org, not the packaged access this test is about.
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            household.OwnerId = staff.Id;
            insert household;
            Account person = new Account(
                Name = 'Maria Garcia',
                Deceased__c = false,
                OwnerId = staff.Id
            );
            insert person;
            String failure = '';

            Test.startTest();
            System.runAs(staff) {
                try {
                    insert new Household_Member__c(
                        Household__c = household.Id,
                        Account__c = person.Id,
                        Role__c = 'Head',
                        Start_Date__c = Date.today()
                    );
                } catch (Exception e) {
                    failure = e.getMessage();
                }
            }
            Test.stopTest();

            Assert.areEqual('', failure, 'A user with no packaged access saves the membership');
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :household.Id].Member_Count__c,
                'And the household counts the person stored as an account'
            );
        }
    }

    /**
     * The junction mode counterpart of the screen test above. The panel reads the person
     * with the running user's own access, so the deceased flag on the account never
     * reaches a user who cannot read it, while upkeep still sees it.
     *
     * The same note about substitution applies: only the org shape is declared, through
     * personAccountOverride. The person is a real account record, read by a real query,
     * and no declared person stands in for it. The panel's name column is not asserted
     * because the person name fields exist on Account only in an org shaped for them, and
     * ADR-0009 forbids this package to name one.
     */
    @IsTest
    static void aScreenNeverShowsAFieldTheUserCannotReadOnAPersonStoredAsAnAccount() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = true;
            User staff = HouseholdTestDataFactory.standardUser('pafls');
            HouseholdTestDataFactory.grantMembershipRead('C01_Junction_Display_Test', staff.Id);
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            insert household;
            // Saved by the same user who will read it back, so that what this test measures is
            // field level access and nothing else, exactly as the contact test above explains.
            Account person = new Account(Name = 'Maria Garcia');
            System.runAs(staff) {
                insert person;
            }
            update new Account(Id = person.Id, Deceased__c = true);
            insert new Household_Member__c(
                Household__c = household.Id,
                Account__c = person.Id,
                Role__c = 'Head',
                Start_Date__c = Date.today()
            );
            Assert.isTrue(
                HouseholdService.getMembers(new Set<Id>{ household.Id }).get(household.Id)[0]
                    .isDeceased,
                'Upkeep sees the whole record, which is how the greetings stay right'
            );

            List<HouseholdController.MemberView> shown;
            Test.startTest();
            System.runAs(staff) {
                shown = HouseholdController.getMembers(household.Id);
            }
            Test.stopTest();

            Assert.areEqual(1, shown.size(), 'The panel still lists the member');
            Assert.areEqual('Head', shown[0].role, 'With the role the membership row carries');
            Assert.isFalse(
                shown[0].isDeceased,
                'A user with no access to the deceased field is not told that she died'
            );
        }
    }

    @IsTest
    static void aBulkMoveMovesEverybodyAtOnceAndAnswersWithEveryHouseholdItTouched() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            Contact amara = HouseholdTestDataFactory.newContact('Ms.', 'Amara', 'Okonkwo');
            insert new List<Contact>{ maria, wei, amara };
            Id mariaHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id weiHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
            Id target = [SELECT AccountId FROM Contact WHERE Id = :amara.Id].AccountId;

            Test.startTest();
            Set<Id> affected = HouseholdService.moveMembers(
                new Set<Id>{ maria.Id, wei.Id },
                target
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ mariaHousehold, weiHousehold, target },
                affected,
                'Both households somebody left and the one they joined are answered'
            );
            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Contact WHERE AccountId = :target],
                'Both people moved in one pass'
            );
        }
    }

    @IsTest
    static void aMoveThatNamesSomebodyWhoIsGoneIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id target = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
            Id goneId = maria.Id;
            delete maria;
            String message = '';

            Test.startTest();
            try {
                HouseholdService.moveMembers(new Set<Id>{ goneId }, target);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_ErrorMoveNotFound,
                message,
                'A stale id is refused rather than quietly dropped from the move'
            );
        }
    }

    @IsTest
    static void peopleStoredAsAccountsMoveInBulkThroughTheJunction() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            HouseholdService.personAccountOverride = true;
            PersonRecordSelector.personRecordOverride = true;
            List<Account> people = new List<Account>{
                new Account(Name = 'Maria Garcia'),
                new Account(Name = 'Wei Lee')
            };
            insert people;
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Garcia Family'),
                HouseholdTestDataFactory.newHousehold('The Lee Family')
            };
            insert households;
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Account__c = people[0].Id,
                    Role__c = 'Head',
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Account__c = people[1].Id,
                    Role__c = 'Spouse or Partner',
                    Start_Date__c = Date.today()
                )
            };

            Test.startTest();
            Set<Id> affected = HouseholdService.moveMembers(
                new Set<Id>{ people[0].Id, people[1].Id },
                households[1].Id
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ households[0].Id, households[1].Id },
                affected,
                'Both households are answered'
            );
            List<Household_Member__c> current = [
                SELECT Account__c, Contact__c, Role__c, Is_Primary__c
                FROM Household_Member__c
                WHERE Household__c = :households[1].Id AND End_Date__c = NULL
                ORDER BY Role__c
            ];
            Assert.areEqual(
                2,
                current.size(),
                'Both people are current members of the new household'
            );
            Assert.areEqual('Head', current[0].Role__c, 'Maria is still the Head');
            Assert.isTrue(current[0].Is_Primary__c, 'And still the primary member');
            Assert.areEqual(null, current[0].Contact__c, 'Neither is recorded as a contact');
        }
    }

    @IsTest
    static void twoPrimaryPeopleMovingIntoOneHouseholdLeaveItOnePrimary() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Contact> people = new List<Contact>{
                HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia'),
                HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee')
            };
            insert people;
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Garcia Family'),
                HouseholdTestDataFactory.newHousehold('The Lee Family'),
                HouseholdTestDataFactory.newHousehold('The Okonkwo Family')
            };
            insert households;
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Contact__c = people[0].Id,
                    Role__c = 'Head',
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = households[1].Id,
                    Contact__c = people[1].Id,
                    Role__c = 'Head',
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                )
            };

            Test.startTest();
            HouseholdService.moveMembers(
                new Set<Id>{ people[0].Id, people[1].Id },
                households[2].Id
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE
                        Household__c = :households[2].Id
                        AND End_Date__c = NULL
                        AND Is_Primary__c = TRUE
                ],
                'Two people who were each primary do not both arrive primary (R-M3)'
            );
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Household__c = :households[2].Id AND End_Date__c = NULL
                ],
                'Both are still members, and both kept their role'
            );
        }
    }

    @IsTest
    static void anArrivingPrimaryDoesNotDisplaceTheOneAlreadyThere() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Contact> people = new List<Contact>{
                HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia'),
                HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee')
            };
            insert people;
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Garcia Family'),
                HouseholdTestDataFactory.newHousehold('The Lee Family')
            };
            insert households;
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = households[0].Id,
                    Contact__c = people[0].Id,
                    Role__c = 'Head',
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = households[1].Id,
                    Contact__c = people[1].Id,
                    Role__c = 'Head',
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                )
            };

            Test.startTest();
            HouseholdService.moveMembers(new Set<Id>{ people[0].Id }, households[1].Id);
            Test.stopTest();

            List<Household_Member__c> primaries = [
                SELECT Contact__c
                FROM Household_Member__c
                WHERE
                    Household__c = :households[1].Id
                    AND End_Date__c = NULL
                    AND Is_Primary__c = TRUE
            ];
            Assert.areEqual(
                1,
                primaries.size(),
                'The household still has exactly one primary (R-M3)'
            );
            Assert.areEqual(
                people[1].Id,
                primaries[0].Contact__c,
                'It is the person who was already there'
            );
        }
    }

    @IsTest
    static void thePrimaryContactIsClearedWhenThatPersonLeavesInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ household, target };
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            john.AccountId = household.Id;
            jane.AccountId = household.Id;
            insert new List<Contact>{ john, jane };
            update new Account(Id = household.Id, Primary_Contact__c = john.Id);

            Test.startTest();
            HouseholdService.moveContact(john.Id, target.Id);
            Test.stopTest();

            Assert.areEqual(
                null,
                [SELECT Primary_Contact__c FROM Account WHERE Id = :household.Id]
                .Primary_Contact__c,
                'The reference to the person who left was cleared (R-H10)'
            );
        }
    }

    @IsTest
    static void thePrimaryContactIsClearedWhenThatPersonLeavesInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ household, target };
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = john.Id,
                    Role__c = 'Head',
                    Is_Primary__c = true,
                    Start_Date__c = Date.today()
                ),
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = jane.Id,
                    Role__c = 'Spouse or Partner',
                    Start_Date__c = Date.today()
                )
            };
            update new Account(Id = household.Id, Primary_Contact__c = john.Id);

            Test.startTest();
            HouseholdService.moveContact(john.Id, target.Id);
            Test.stopTest();

            Assert.areEqual(
                null,
                [SELECT Primary_Contact__c FROM Account WHERE Id = :household.Id]
                .Primary_Contact__c,
                'The reference to the person who left was cleared (R-H10)'
            );
        }
    }

    @IsTest
    static void nobodyIsPromotedIntoThePrimaryContactTheLeaverGaveUp() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ household, target };
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            john.AccountId = household.Id;
            jane.AccountId = household.Id;
            insert new List<Contact>{ john, jane };
            update new Account(Id = household.Id, Primary_Contact__c = john.Id);

            Test.startTest();
            HouseholdService.moveContact(john.Id, target.Id);
            Test.stopTest();

            Account saved = [
                SELECT Primary_Contact__c, Member_Count__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(1, saved.Member_Count__c, 'Jane is still a member');
            Assert.areEqual(
                null,
                saved.Primary_Contact__c,
                'Jane was not silently promoted: the next member is proposed, not assigned (R-H10)'
            );
        }
    }

    @IsTest
    static void aPrimaryContactWhoStaysIsLeftAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ household, target };
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            john.AccountId = household.Id;
            jane.AccountId = household.Id;
            insert new List<Contact>{ john, jane };
            update new Account(Id = household.Id, Primary_Contact__c = jane.Id);

            Test.startTest();
            HouseholdService.moveContact(john.Id, target.Id);
            Test.stopTest();

            Assert.areEqual(
                jane.Id,
                [SELECT Primary_Contact__c FROM Account WHERE Id = :household.Id]
                .Primary_Contact__c,
                'The primary contact who is still a member is untouched'
            );
        }
    }

    @IsTest
    static void anOrganizationKeepsItsPrimaryContactWhenSomebodyLeaves() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account organization = new Account(Name = 'Riverside Shelter');
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ organization, household };
            Contact staff = HouseholdTestDataFactory.newContact('Ms.', 'Ada', 'Nkosi');
            staff.AccountId = organization.Id;
            insert staff;
            update new Account(Id = organization.Id, Primary_Contact__c = staff.Id);

            Test.startTest();
            HouseholdService.moveContact(staff.Id, household.Id);
            Test.stopTest();

            Assert.areEqual(
                staff.Id,
                [SELECT Primary_Contact__c FROM Account WHERE Id = :organization.Id]
                .Primary_Contact__c,
                'An organization shares the field but not the rule (R-O3), so it is left alone'
            );
        }
    }

    @IsTest
    static void peopleAreJoinedToSeveralHouseholdsAtOnceInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Account> households = new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Smith Family'),
                HouseholdTestDataFactory.newHousehold('The Garcia Family')
            };
            insert households;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert new List<Contact>{ john, jane, maria };

            Test.startTest();
            Set<Id> affected = HouseholdService.addMembers(
                new Map<Id, Set<Id>>{
                    households[0].Id => new Set<Id>{ john.Id, jane.Id },
                    households[1].Id => new Set<Id>{ maria.Id }
                }
            );
            Test.stopTest();

            Assert.areEqual(2, affected.size(), 'Both households were touched');
            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Household_Member__c WHERE End_Date__c = NULL],
                'One membership row per person'
            );
            Assert.areEqual(
                2,
                HouseholdService.getMembers(new Set<Id>{ households[0].Id })
                    .get(households[0].Id)
                    .size(),
                'The Smiths are members of their household'
            );
            Assert.areEqual(
                households[1].Id,
                HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id }).get(maria.Id),
                'Maria belongs to the household she was joined to'
            );
        }
    }

    @IsTest
    static void joiningSomebodyTwiceLeavesThemOneMembership() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            Map<Id, Set<Id>> joining = new Map<Id, Set<Id>>{
                household.Id => new Set<Id>{ john.Id }
            };

            Test.startTest();
            HouseholdService.addMembers(joining);
            HouseholdService.addMembers(joining);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Household_Member__c WHERE End_Date__c = NULL],
                'Somebody who is already a current member is left alone'
            );
        }
    }

    @IsTest
    static void joiningInContactModeIsTheirOwnHouseholdField() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account first = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Account second = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ first, second };
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            john.AccountId = first.Id;
            insert john;

            Test.startTest();
            Set<Id> affected = HouseholdService.addMembers(
                new Map<Id, Set<Id>>{ second.Id => new Set<Id>{ john.Id } }
            );
            Test.stopTest();

            Assert.areEqual(
                second.Id,
                [SELECT AccountId FROM Contact WHERE Id = :john.Id].AccountId,
                'The contact now points at the household he joined'
            );
            Assert.isTrue(
                affected.contains(first.Id),
                'The household he left is in the answer, so the caller can settle it up'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'Contact membership writes no membership rows (R-M1)'
            );
        }
    }

    @IsTest
    static void joiningAnOrganizationIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account organization = new Account(Name = 'Riverside Trust');
            insert organization;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;

            String message = '';
            Test.startTest();
            try {
                HouseholdService.addMembers(
                    new Map<Id, Set<Id>>{ organization.Id => new Set<Id>{ john.Id } }
                );
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_ErrorNotAHousehold,
                message,
                'An organization is never a household to join'
            );
        }
    }

    /**
     * The delete guard, ADR-0036. The probe it uses asks two Salesforce Nonprofit Cloud
     * objects that do not exist in this org and cannot be created in a test, so the probe's
     * answer is injected and both outcomes are exercised against it.
     */
    @IsTest
    static void anEmptyHouseholdWithNothingElseDependingOnItIsDeleted() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>();

            Test.startTest();
            HouseholdService.moveContact(maria.Id, toHousehold);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
                'Nothing outside BarnCRM points at the empty household, so it was deleted'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = :ErrorLogger.SEVERITY_INFO],
                'An ordinary tidy-up is not worth telling anybody about'
            );
        }
    }

    @IsTest
    static void anEmptyHouseholdSomethingElseDependsOnIsKeptAndReported() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
            // As though this household were also a Nonprofit Cloud household: an account with a
            // native household group hanging off it, whose members BarnCRM cannot see.
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{ fromHousehold };

            Test.startTest();
            HouseholdService.moveContact(maria.Id, toHousehold);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
                'Deleting the household would have destroyed the records that depend on it'
            );
            List<Error_Log__c> reported = [
                SELECT Message__c, Severity__c, Context__c
                FROM Error_Log__c
                WHERE Severity__c = :ErrorLogger.SEVERITY_INFO
            ];
            Assert.areEqual(1, reported.size(), 'The household that was kept was reported once');
            Assert.areEqual(
                ErrorLogger.SEVERITY_INFO,
                reported[0].Severity__c,
                'Leaving the household alone is the correct outcome, not a failure'
            );
            Assert.isTrue(
                reported[0].Message__c.contains('The Garcia Family'),
                'The message names the household an administrator has to go and look at'
            );
            Assert.isTrue(
                reported[0].Message__c.contains(String.valueOf(fromHousehold)),
                'The message carries the household record identifier'
            );
        }
    }

    // ---------------------------------------------------------- native household guards

    /**
     * Mutual exclusion (product-plan Section 11.2 item 9). afterMembershipChange still
     * recalculates the member count, which is BarnCRM's own bookkeeping, but leaves the
     * name and greetings of a household that already carries a native Nonprofit Cloud
     * household group exactly as they were.
     */
    @IsTest
    static void namingIsSkippedForAHouseholdWithANativeGroupButMemberCountStillUpdates() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Account native = HouseholdTestDataFactory.newHousehold('Old native name');
            insert native;
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{ native.Id };

            Test.startTest();
            HouseholdService.moveContact(maria.Id, native.Id);
            Test.stopTest();

            Account after = [SELECT Name, Member_Count__c FROM Account WHERE Id = :native.Id];
            Assert.areEqual(
                'Old native name',
                after.Name,
                'The name of a household with a native group is never rewritten'
            );
            Assert.areEqual(
                1,
                after.Member_Count__c,
                'The member count is BarnCRM\'s own bookkeeping and still updates'
            );
        }
    }

    /**
     * Auto-creation, junction mode, contact stored as a person. The weaker but safe rule:
     * a contact whose AccountId already points at an Account carrying a native household
     * group gets no BarnCRM household.
     */
    @IsTest
    static void aContactAlreadyLinkedToANativeHouseholdGetsNoNewHouseholdInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account native = new Account(Name = 'Native household account');
            insert native;
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{ native.Id };
            Contact maria = new Contact(
                Salutation = 'Ms.',
                FirstName = 'Maria',
                LastName = 'Garcia',
                AccountId = native.Id
            );

            Test.startTest();
            insert maria;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c = :maria.Id],
                'No BarnCRM household was created for a contact already linked to a native household'
            );
        }
    }

    /**
     * Auto-creation, junction mode, person stored as an account. Here the person's own
     * Account is the person, so the same rule is asked of the Account itself.
     */
    @IsTest
    static void aPersonAccountThatAlreadyCarriesANativeGroupGetsNoBarnCRMHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = true;
            Account person = new Account(Name = 'Maria Garcia');
            insert person;
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{ person.Id };

            Test.startTest();
            HouseholdService.createHouseholdsForPersonAccounts(new List<SObject>{ person });
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Account__c = :person.Id],
                'No BarnCRM household was created for a person account that already carries a native household group'
            );
        }
    }

    /**
     * PEOPLE-7. The hidden contact behind a person stored as an account, handed to
     * addMembers, joins as that account: one membership, on the account side, and no row
     * naming the contact.
     */
    @IsTest
    static void thePersonContactBehindAnAccountJoinsAsTheAccount() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = true;
            Account person = new Account(Name = 'Maria Garcia');
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Household');
            insert new List<Account>{ person, household };
            Contact behind = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert behind;
            PersonRecordSelector.accountBehindContactOverride = new Map<Id, Id>{
                behind.Id => person.Id
            };

            Test.startTest();
            HouseholdService.addMembers(
                new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ behind.Id } }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Household__c = :household.Id AND Account__c = :person.Id
                ],
                'The person joins by the account side'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Household__c = :household.Id AND Contact__c = :behind.Id
                ],
                'No membership names the hidden contact'
            );
        }
    }

    /**
     * The short circuit: an org OrgShapeDetector reports as having no native household
     * groups at all is never asked the per-record question.
     */
    @IsTest
    static void theNativePredicateShortCircuitsWhenTheOrgHasNoNativeGroupsAtAll() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = false;
            OrgShapeDetector.overrideShape = shape;
            Set<Id> candidates = new Set<Id>{ UserInfo.getUserId() };

            Test.startTest();
            Integer before = Limits.getQueries();
            Set<Id> result = HouseholdSelector.nativeHouseholdAccountsAmong(candidates);
            Integer after = Limits.getQueries();
            Test.stopTest();

            Assert.isTrue(
                result.isEmpty(),
                'No accounts are treated as native when the org has none'
            );
            Assert.areEqual(before, after, 'The short circuit runs no query at all');
        }
    }

    // ---------------------------------------------------------- moving out of one of several

    /**
     * A child in two households, moved out of one of them, stays in the other: only the
     * membership in the household named as the one they leave ends.
     */
    @IsTest
    static void movingAPersonOutOfOneHouseholdLeavesTheirOtherHouseholdAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account first = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account second = HouseholdTestDataFactory.newHousehold('The Lee Family');
            Account target = HouseholdTestDataFactory.newHousehold('The Okonkwo Family');
            insert new List<Account>{ first, second, target };
            Contact ana = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Garcia');
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert new List<Contact>{ ana, maria };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = first.Id, Contact__c = ana.Id),
                new Household_Member__c(Household__c = first.Id, Contact__c = maria.Id),
                new Household_Member__c(Household__c = second.Id, Contact__c = ana.Id)
            };

            Test.startTest();
            HouseholdService.moveContact(ana.Id, target.Id, first.Id);
            Test.stopTest();

            Map<Id, Integer> current = new Map<Id, Integer>();
            for (Household_Member__c row : [
                SELECT Household__c
                FROM Household_Member__c
                WHERE Contact__c = :ana.Id AND End_Date__c = NULL
            ]) {
                Integer seen = current.get(row.Household__c);
                current.put(row.Household__c, seen == null ? 1 : seen + 1);
            }
            Assert.isFalse(
                current.containsKey(first.Id),
                'Ana left the household she was moved out of'
            );
            Assert.areEqual(1, current.get(second.Id), 'Ana is still in her other household');
            Assert.areEqual(1, current.get(target.Id), 'Ana joined the household she was moved to');
            Map<Id, Account> counts = new Map<Id, Account>(
                [
                    SELECT Member_Count__c
                    FROM Account
                    WHERE Id IN :new Set<Id>{ first.Id, second.Id, target.Id }
                ]
            );
            Assert.areEqual(1, counts.get(first.Id).Member_Count__c, 'Maria is left in the first');
            Assert.areEqual(
                1,
                counts.get(second.Id).Member_Count__c,
                'The second still counts Ana'
            );
            Assert.areEqual(1, counts.get(target.Id).Member_Count__c, 'The target counts Ana');
        }
    }

    /**
     * A single move stands the person and membership handlers down while it moves, and
     * settles the households itself once. The handlers are back on straight afterwards, so
     * the next save in the same transaction is looked after as usual.
     */
    @IsTest
    static void theHandlersAreBackOnAfterAMove() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account first = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account target = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ first, target };
            Contact ana = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Garcia');
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert new List<Contact>{ ana, maria };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = first.Id, Contact__c = ana.Id),
                new Household_Member__c(Household__c = first.Id, Contact__c = maria.Id)
            };

            Test.startTest();
            HouseholdService.moveContact(ana.Id, target.Id, first.Id);
            Assert.areEqual(
                'The Garcia Family',
                [SELECT Name FROM Account WHERE Id = :target.Id].Name,
                'The move settled the household she joined: it is named from her'
            );
            update new Contact(Id = ana.Id, LastName = 'Garcia-Lee');
            Test.stopTest();

            Assert.areEqual(
                'The Garcia-Lee Family',
                [SELECT Name FROM Account WHERE Id = :target.Id].Name,
                'The next save after the move is looked after by the handlers again'
            );
        }
    }

    /**
     * The guard against deleting a household that only looks empty: it names the households
     * any contact points at, and only those.
     */
    @IsTest
    static void anOccupiedHouseholdIsNamedAsOccupied() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account occupied = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account empty = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ occupied, empty };
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            maria.AccountId = occupied.Id;
            insert maria;

            Test.startTest();
            Set<Id> result = HouseholdSelector.householdsWithAnyContact(
                new Set<Id>{ occupied.Id, empty.Id }
            );
            Test.stopTest();

            Assert.areEqual(new Set<Id>{ occupied.Id }, result, 'Only the occupied household');
        }
    }

    // ---------------------------------------------------------- one read per upkeep pass

    /** An org shape with no native household groups, so the mutual exclusion asks nothing. */
    private static OrgShapeDetector.OrgShape shapeWithoutNativeHouseholds() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNativeHouseholdGroups = false;
        shape.hasPersonAccounts = false;
        return shape;
    }

    /**
     * PEOPLE-34: one upkeep pass reads the households once and their members once. In
     * contact mode that is two queries, the households and the contacts in them, where the
     * pass used to read both again for the primary, the count, the wording and the tidy-up.
     */
    @IsTest
    static void oneUpkeepPassReadsTheDatabaseTwiceInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            OrgShapeDetector.overrideShape = shapeWithoutNativeHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            insert new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );
            Set<Id> householdIds = new Set<Id>{ household.Id };
            // A first pass settles the household and fills every per-transaction cache, so
            // the pass measured has nothing to save and only its reads are counted.
            HouseholdService.afterMembershipChange(householdIds, false);

            Test.startTest();
            Integer before = Limits.getQueries();
            HouseholdService.afterMembershipChange(householdIds, true);
            Integer used = Limits.getQueries() - before;
            Test.stopTest();

            Assert.areEqual(2, used, 'One read of the households and one of their contacts');
        }
    }

    /**
     * PEOPLE-34 in junction mode: three queries, the households, their membership rows and
     * the contacts those rows name.
     */
    @IsTest
    static void oneUpkeepPassReadsTheDatabaseThreeTimesInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            OrgShapeDetector.overrideShape = shapeWithoutNativeHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = john.Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            );
            Set<Id> householdIds = new Set<Id>{ household.Id };
            HouseholdService.afterMembershipChange(householdIds, false);

            Test.startTest();
            Integer before = Limits.getQueries();
            HouseholdService.afterMembershipChange(householdIds, true);
            Integer used = Limits.getQueries() - before;
            Test.stopTest();

            Assert.areEqual(
                3,
                used,
                'One read of the households, one of the membership rows, one of the contacts'
            );
        }
    }

    /**
     * PEOPLE-34 in bulk: 200 households joined without upkeep, so each has a stale count,
     * name and primary, are all put right by one pass.
     */
    @IsTest
    static void oneUpkeepPassSettlesTwoHundredHouseholds() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            OrgShapeDetector.overrideShape = shapeWithoutNativeHouseholds();
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                households.add(HouseholdTestDataFactory.newHousehold('Household ' + i));
            }
            insert households;
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');
            insert people;
            List<Household_Member__c> rows = new List<Household_Member__c>();
            for (Integer i = 0; i < 200; i++) {
                rows.add(
                    new Household_Member__c(
                        Household__c = households[i].Id,
                        Contact__c = people[i].Id,
                        Role__c = 'Head',
                        Is_Primary__c = true,
                        Start_Date__c = Date.today()
                    )
                );
            }
            AutomationControl.bypass('HouseholdMemberTriggerHandler');
            insert rows;
            AutomationControl.clearBypass('HouseholdMemberTriggerHandler');
            Set<Id> householdIds = new Map<Id, Account>(households).keySet();

            Test.startTest();
            HouseholdService.afterMembershipChange(householdIds, true);
            Test.stopTest();

            Integer settled = 0;
            for (Account household : [
                SELECT Name, Member_Count__c, Primary_Contact__c
                FROM Account
                WHERE Id IN :householdIds
            ]) {
                Boolean right =
                    household.Member_Count__c == 1 &&
                    household.Primary_Contact__c != null &&
                    household.Name.startsWith('The Bulk');
                settled += right ? 1 : 0;
            }
            Assert.areEqual(
                200,
                settled,
                'Every household was counted, named and given its primary'
            );
        }
    }
}
