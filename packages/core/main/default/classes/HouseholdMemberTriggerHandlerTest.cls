/**
 * Household upkeep in the flexible membership mode: every path a membership can take.
 * Canonical model R-H11 and R-H12, plan Section 9.4.
 */
@IsTest(testFor='ApexClass:HouseholdMemberTriggerHandler')
private class HouseholdMemberTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Account household;
    private static Contact john;

    private static void setUp() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        household = HouseholdTestDataFactory.newHousehold('Placeholder');
        Database.insert(household, AccessLevel.SYSTEM_MODE);
        john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;
    }

    private static Household_Member__c membership(Id personId) {
        return new Household_Member__c(
            Household__c = household.Id,
            Contact__c = personId,
            Role__c = 'Head',
            Is_Primary__c = true,
            Start_Date__c = Date.today()
        );
    }

    private static Account reload() {
        return [
            SELECT Name, Member_Count__c
            FROM Account
            WHERE Id = :household.Id
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void addingAMembershipCountsAndNamesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            setUp();

            Test.startTest();
            insert membership(john.Id);
            Test.stopTest();

            Account saved = reload();
            Assert.areEqual(1, saved.Member_Count__c, 'John is counted');
            Assert.areEqual(
                'The Smith Family',
                saved.Name,
                'The household is named from its member'
            );
        }
    }

    @IsTest
    static void endingAMembershipTodayTakesThePersonOutOfTheHousehold() {
        System.runAs(TestUsers.admin()) {
            setUp();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Household_Member__c row = membership(john.Id);
            insert row;

            Test.startTest();
            update new Household_Member__c(Id = row.Id, End_Date__c = Date.today());
            Test.stopTest();

            Assert.areEqual(0, reload().Member_Count__c, 'A membership that ended today is over');
        }
    }

    @IsTest
    static void changingTheHouseholdOnAMembershipCorrectsBoth() {
        System.runAs(TestUsers.admin()) {
            setUp();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Account other = HouseholdTestDataFactory.newHousehold('Other');
            Database.insert(other, AccessLevel.SYSTEM_MODE);
            Household_Member__c row = membership(john.Id);
            insert row;

            Test.startTest();
            update new Household_Member__c(Id = row.Id, Household__c = other.Id);
            Test.stopTest();

            Assert.areEqual(0, reload().Member_Count__c, 'The household John left counts nobody');
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :other.Id].Member_Count__c,
                'The household John joined counts him'
            );
        }
    }

    @IsTest
    static void removingTheLastMembershipTidiesTheHouseholdAway() {
        System.runAs(TestUsers.admin()) {
            setUp();
            Household_Member__c row = membership(john.Id);
            insert row;

            Test.startTest();
            delete row;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :household.Id],
                'The emptied household went too'
            );
        }
    }

    @IsTest
    static void restoringAMembershipCountsThePersonAgain() {
        System.runAs(TestUsers.admin()) {
            setUp();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Household_Member__c row = membership(john.Id);
            insert row;
            delete row;

            Test.startTest();
            undelete row;
            Test.stopTest();

            Assert.areEqual(1, reload().Member_Count__c, 'John is counted again');
        }
    }

    // ------------------------------------------------ what a membership row may say (PEOPLE-25)

    @IsTest
    static void aSecondCurrentMembershipOfOnePersonInOneHouseholdIsRefused() {
        System.runAs(TestUsers.admin()) {
            setUp();
            insert membership(john.Id);
            Household_Member__c again = membership(john.Id);
            again.Is_Primary__c = false;

            Test.startTest();
            Database.SaveResult result = Database.insert(again, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'John is already a current member');
            Assert.areEqual(
                Label.Core_Households_ErrorAlreadyCurrentMember,
                result.getErrors()[0].getMessage(),
                'The person is told why'
            );
            Assert.areEqual(1, reload().Member_Count__c, 'John is counted once');
        }
    }

    @IsTest
    static void twoRowsForOnePersonInOneSaveAreNotBothCurrent() {
        System.runAs(TestUsers.admin()) {
            setUp();
            Household_Member__c first = membership(john.Id);
            Household_Member__c second = membership(john.Id);
            second.Is_Primary__c = false;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Household_Member__c>{ first, second },
                false
            );
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'The first is saved');
            Assert.isFalse(results[1].isSuccess(), 'The second is refused');
        }
    }

    @IsTest
    static void anEndedMembershipAndANewOneMayBothBeKept() {
        System.runAs(TestUsers.admin()) {
            setUp();
            Household_Member__c ended = membership(john.Id);
            ended.Start_Date__c = Date.today().addYears(-2);
            ended.End_Date__c = Date.today().addYears(-1);
            ended.Is_Primary__c = false;
            insert ended;

            Test.startTest();
            insert membership(john.Id);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c = :john.Id],
                'History and the current membership side by side'
            );
        }
    }

    @IsTest
    static void bringingBackAnEndedRowBesideACurrentOneIsRefused() {
        System.runAs(TestUsers.admin()) {
            setUp();
            Household_Member__c ended = membership(john.Id);
            ended.End_Date__c = Date.today().addYears(-1);
            ended.Is_Primary__c = false;
            insert new List<Household_Member__c>{ ended, membership(john.Id) };

            Test.startTest();
            ended.End_Date__c = null;
            Database.SaveResult result = Database.update(ended, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'Two current memberships would count John twice');
        }
    }

    @IsTest
    static void aMembershipMustNameExactlyOnePerson() {
        System.runAs(TestUsers.admin()) {
            setUp();
            Household_Member__c nobody = membership(john.Id);
            nobody.Contact__c = null;
            Account other = new Account(Name = 'Some account');
            insert other;
            Household_Member__c both = membership(john.Id);
            both.Account__c = other.Id;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Household_Member__c>{ nobody, both },
                false
            );
            Test.stopTest();

            Assert.isFalse(results[0].isSuccess(), 'A row naming nobody is refused (R-M4)');
            Assert.isFalse(results[1].isSuccess(), 'A row naming two people is refused (R-M4)');
        }
    }

    @IsTest
    static void aRowLeftNamingNobodyCanStillBeEnded() {
        System.runAs(TestUsers.admin()) {
            setUp();
            Household_Member__c row = membership(john.Id);
            insert row;
            AutomationControl.bypass('ContactTriggerHandler');
            delete john;
            AutomationControl.clearBypass('ContactTriggerHandler');

            Test.startTest();
            row.End_Date__c = Date.today();
            Database.SaveResult result = Database.update(row, false);
            Test.stopTest();

            Assert.isTrue(result.isSuccess(), 'Tidying up an orphaned row is never blocked');
        }
    }
}
