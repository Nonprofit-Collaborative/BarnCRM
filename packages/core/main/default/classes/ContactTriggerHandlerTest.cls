/**
 * The household upkeep that happens when a person is saved, changed, deleted, or restored.
 */
@IsTest(testFor='ApexClass:ContactTriggerHandler')
private class ContactTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void changingASurnameRenamesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

            Test.startTest();
            update new Contact(Id = maria.Id, LastName = 'Garcia-Lee');
            Test.stopTest();

            Assert.areEqual(
                'The Garcia-Lee Family',
                [SELECT Name FROM Account WHERE Id = :household].Name,
                'The household follows the surname'
            );
        }
    }

    @IsTest
    static void markingSomeoneDeceasedRewritesTheGreetings() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            Contact john = new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );
            Contact jane = new Contact(
                Salutation = 'Mrs.',
                FirstName = 'Jane',
                LastName = 'Smith',
                AccountId = household.Id
            );
            insert new List<Contact>{ john, jane };

            Test.startTest();
            update new Contact(Id = jane.Id, Deceased__c = true);
            Test.stopTest();

            Assert.areEqual(
                'John',
                [SELECT Household_Informal_Greeting__c FROM Account WHERE Id = :household.Id]
                .Household_Informal_Greeting__c,
                'Jane is no longer greeted'
            );
        }
    }

    @IsTest
    static void deletingTheLastMemberKeepsTheHouseholdSoTheyCanBeRestored() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            Assert.isTrue(settings.Delete_Empty_Households__c, 'The tidy-up is on');
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            delete maria;
            Assert.areEqual(
                0,
                [SELECT Member_Count__c FROM Account WHERE Id = :household].Member_Count__c,
                'The household is kept, recounted to nobody, because Maria was deleted, not moved'
            );

            Test.startTest();
            undelete maria;
            Test.stopTest();

            Account restored = [SELECT Member_Count__c FROM Account WHERE Id = :household];
            Assert.areEqual(1, restored.Member_Count__c, 'Maria is a member again');
            Assert.areEqual(
                household,
                [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId,
                'Maria came back into her household'
            );
        }
    }

    @IsTest
    static void restoringAPersonPutsTheCountBack() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            delete maria;

            Test.startTest();
            undelete maria;
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :household].Member_Count__c,
                'Maria is counted again'
            );
        }
    }

    @IsTest
    static void movingSomeoneByEditingTheirHouseholdRecountsBoth() {
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
            update new Contact(Id = maria.Id, AccountId = toHousehold);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT Member_Count__c FROM Account WHERE Id = :fromHousehold].Member_Count__c,
                'The household Maria left counts nobody'
            );
            // Wei is that household's primary contact, so his surname comes first (R-H5).
            Assert.areEqual(
                'Lee and Garcia Household',
                [SELECT Name FROM Account WHERE Id = :toHousehold].Name,
                'The household Maria joined lists both surnames'
            );
        }
    }

    /**
     * The four tests below cover a person stored as a contact in junction mode. Every
     * other junction mode lifecycle test in this package uses a person account, so this
     * half of the shape had no coverage at all: the contact trigger read the household
     * from `Contact.AccountId`, which in junction mode is an employer or nothing, so a
     * rename, a delete and an undelete all quietly did nothing.
     *
     * This is the only junction shape a Platform-only org can run (ADR-0013), and it is
     * also the shape of a mixed org, where some people are accounts and some are contacts.
     */
    @IsTest
    static void changingASurnameInJunctionModeRenamesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [
                SELECT Household__c
                FROM Household_Member__c
                WHERE Contact__c = :maria.Id
            ]
            .Household__c;

            Test.startTest();
            update new Contact(Id = maria.Id, LastName = 'Garcia-Lee');
            Test.stopTest();

            Assert.areEqual(
                'The Garcia-Lee Family',
                [SELECT Name FROM Account WHERE Id = :household].Name,
                'The household follows the surname when membership is a row rather than a reference'
            );
        }
    }

    @IsTest
    static void deletingTheLastMemberInJunctionModeKeepsTheHouseholdForTheUndelete() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [
                SELECT Household__c
                FROM Household_Member__c
                WHERE Contact__c = :maria.Id
            ]
            .Household__c;
            delete maria;
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Household__c = :household],
                'The membership row goes with the person rather than being left naming nobody'
            );
            Assert.areEqual(
                0,
                [SELECT Member_Count__c FROM Account WHERE Id = :household].Member_Count__c,
                'The household is kept, recounted to nobody, because Maria was deleted, not moved'
            );

            Test.startTest();
            undelete maria;
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Household__c = :household AND Contact__c = :maria.Id
                ],
                'Her membership came back into the kept household'
            );
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :household].Member_Count__c,
                'She is counted again'
            );
        }
    }

    @IsTest
    static void deletingOneOfTwoMembersInJunctionModeRecountsAndRenames() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Rivera Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Rivera');
            Contact luis = HouseholdTestDataFactory.newContact('Mr.', 'Luis', 'Rivera');
            insert new List<Contact>{ maria, luis };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = household.Id, Contact__c = maria.Id),
                new Household_Member__c(Household__c = household.Id, Contact__c = luis.Id)
            };

            Test.startTest();
            delete luis;
            Test.stopTest();

            Account after = [
                SELECT Member_Count__c, Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(
                1,
                after.Member_Count__c,
                'The household counts only the people still in it'
            );
            Assert.areEqual(
                'Maria',
                after.Household_Informal_Greeting__c,
                'Luis is no longer greeted once he is gone'
            );
        }
    }

    @IsTest
    static void restoringAContactInJunctionModePutsThemBackInTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Rivera Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Rivera');
            Contact luis = HouseholdTestDataFactory.newContact('Mr.', 'Luis', 'Rivera');
            insert new List<Contact>{ maria, luis };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = household.Id, Contact__c = maria.Id),
                new Household_Member__c(Household__c = household.Id, Contact__c = luis.Id)
            };
            delete luis;

            Test.startTest();
            undelete luis;
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Household_Member__c WHERE Household__c = :household.Id],
                'The membership row comes back out of the recycle bin with the person'
            );
            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :household.Id].Member_Count__c,
                'The household counts the restored person again'
            );
        }
    }

    @IsTest
    static void correctingOnlyTheCaseOfASurnameRenamesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact person = HouseholdTestDataFactory.newContact('Mr.', 'Sean', 'Mcdonald');
            insert person;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId;

            Test.startTest();
            update new Contact(Id = person.Id, LastName = 'McDonald');
            Test.stopTest();

            Account saved = [
                SELECT Name, Household_Formal_Greeting__c
                FROM Account
                WHERE Id = :household
            ];
            Assert.isTrue(
                'The McDonald Family'.equals(saved.Name),
                'A case-only correction reaches the household name: ' + saved.Name
            );
            Assert.isTrue(
                saved.Household_Formal_Greeting__c.contains('McDonald'),
                'And the greeting: ' + saved.Household_Formal_Greeting__c
            );
        }
    }

    @IsTest
    static void changingEmployerAndSurnameTogetherInJunctionModeRenamesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account employer = new Account(Name = 'Riverside Library');
            Database.insert(new List<Account>{ household, employer }, AccessLevel.SYSTEM_MODE);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = maria.Id,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            // One save that both changes her employer (her account in junction mode) and
            // her surname: the second change used to be skipped because of the first.
            update new Contact(Id = maria.Id, AccountId = employer.Id, LastName = 'Garcia-Lee');
            Test.stopTest();

            Assert.areEqual(
                'The Garcia-Lee Family',
                [SELECT Name FROM Account WHERE Id = :household.Id].Name,
                'The household she belongs to follows the surname'
            );
            Assert.areEqual(
                'Riverside Library',
                [SELECT Name FROM Account WHERE Id = :employer.Id].Name,
                'The employer is not a household and is left alone'
            );
        }
    }

    private static Account organization(String name) {
        Account result = new Account(Name = name);
        Schema.RecordTypeInfo type = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization');
        if (type != null) {
            result.RecordTypeId = type.getRecordTypeId();
        }
        return result;
    }

    @IsTest
    static void pointingSomeoneInAHouseholdAtAnOrganizationIsRefusedInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account library = organization('Riverside Library');
            insert library;
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            String refused;

            Test.startTest();
            try {
                update new Contact(Id = maria.Id, AccountId = library.Id);
            } catch (DmlException thrown) {
                refused = thrown.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Households_ErrorPersonToOrganization, refused);
            Assert.areEqual(
                household,
                [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId,
                'Maria stays in her household'
            );
        }
    }

    @IsTest
    static void someoneAlreadyAtAnOrganizationCanBePointedAtAnother() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account library = organization('Riverside Library');
            Account trust = organization('Riverside Community Trust');
            insert new List<Account>{ library, trust };
            Contact tom = HouseholdTestDataFactory.newContact('Mr.', 'Tom', 'Rivera');
            tom.AccountId = library.Id;
            insert tom;

            Test.startTest();
            update new Contact(Id = tom.Id, AccountId = trust.Id);
            Test.stopTest();

            Assert.areEqual(
                trust.Id,
                [SELECT AccountId FROM Contact WHERE Id = :tom.Id].AccountId,
                'A contact at an organization was never in a household: the change stands'
            );
        }
    }

    @IsTest
    static void inJunctionModeTheAccountIsAnEmployerAndMayChange() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account library = organization('Riverside Library');
            Database.insert(new List<Account>{ household, library }, AccessLevel.SYSTEM_MODE);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            maria.AccountId = household.Id;
            insert maria;

            Test.startTest();
            update new Contact(Id = maria.Id, AccountId = library.Id);
            Test.stopTest();

            Assert.areEqual(
                library.Id,
                [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId,
                'Junction mode keeps households in membership rows, so this is allowed'
            );
        }
    }
}
