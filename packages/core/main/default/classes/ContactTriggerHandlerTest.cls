/**
 * The household upkeep that happens when a person is saved, changed, deleted, or restored.
 */
@IsTest(testFor='ApexClass:ContactTriggerHandler')
private class ContactTriggerHandlerTest {
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
            insert household;
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
    static void deletingTheLastMemberTidiesTheHouseholdAway() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

            Test.startTest();
            delete maria;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :household],
                'The empty household went too'
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
            Assert.areEqual(
                'Garcia and Lee Household',
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
    static void deletingTheLastMemberInJunctionModeTidiesTheHouseholdAway() {
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
            delete maria;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Household__c = :household],
                'The membership row goes with the person rather than being left naming nobody'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :household],
                'The household nobody is left in is tidied away'
            );
        }
    }

    @IsTest
    static void deletingOneOfTwoMembersInJunctionModeRecountsAndRenames() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Rivera Family');
            insert household;
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
            insert household;
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
}
