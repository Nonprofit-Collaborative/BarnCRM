/**
 * Household upkeep in the flexible membership mode: every path a membership can take.
 * Canonical model R-H11 and R-H12, plan Section 9.4.
 */
@IsTest(testFor='ApexClass:HouseholdMemberTriggerHandler')
private class HouseholdMemberTriggerHandlerTest {
    private static Account household;
    private static Contact john;

    private static void setUp() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        household = HouseholdTestDataFactory.newHousehold('Placeholder');
        insert household;
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
        return [SELECT Name, Member_Count__c FROM Account WHERE Id = :household.Id];
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
            insert other;
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
}
