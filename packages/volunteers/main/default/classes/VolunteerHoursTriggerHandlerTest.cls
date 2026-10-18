/**
 * The rules nobody entering hours has to think about: the household arrives by itself in either
 * membership mode (R-VG2), the job comes from the shift (R-VG3), and merging two people moves
 * their hours, approved ones included.
 */
@IsTest(testFor='ApexClass:VolunteerHoursTriggerHandler, ApexTrigger:VolunteerHoursTrigger')
private class VolunteerHoursTriggerHandlerTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.job('Food pantry sort');
        }
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    private static Volunteer_Hours__c reread(Id hoursId) {
        return [
            SELECT Id, Contact__c, Account__c, Household__c, Volunteer_Job__c, Status__c
            FROM Volunteer_Hours__c
            WHERE Id = :hoursId
        ];
    }

    @IsTest
    static void householdComesFromTheContactInContactMode() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Account household = VolunteersTestData.household('The Rivera Family');
            Contact person = VolunteersTestData.contact('Rivera', household.Id);
            Contact other = VolunteersTestData.contact('Okafor', null);
            Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, jobId(), 2);

            Test.startTest();
            insert hours;
            Id credited = reread(hours.Id).Household__c;
            update new Volunteer_Hours__c(Id = hours.Id, Contact__c = other.Id);
            Test.stopTest();

            Assert.areEqual(household.Id, credited, 'The household comes from the person.');
            Assert.isNull(
                reread(hours.Id).Household__c,
                'A new person with no household leaves no household behind.'
            );
        }
    }

    @IsTest
    static void householdComesFromTheMembershipInJunctionMode() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = VolunteersTestData.household('The Nolan Family');
            Contact person = VolunteersTestData.contact('Nolan', null);
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = person.Id,
                Role__c = 'Head'
            );
            Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, jobId(), 2);

            Test.startTest();
            insert hours;
            Test.stopTest();

            Assert.areEqual(
                household.Id,
                reread(hours.Id).Household__c,
                'In junction mode the household is the membership Core answers with.'
            );
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountGetsTheirHousehold() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            Account household = VolunteersTestData.household('The Okafor Family');
            insert new Household_Member__c(
                Household__c = household.Id,
                Account__c = person.Id,
                Role__c = 'Head'
            );
            Volunteer_Hours__c hours = VolunteersTestData.newHours(null, jobId(), 2);
            hours.Account__c = person.Id;

            Test.startTest();
            insert hours;
            Test.stopTest();

            Volunteer_Hours__c saved = reread(hours.Id);
            Assert.areEqual(person.Id, saved.Account__c, 'The person is the account.');
            Assert.areEqual(household.Id, saved.Household__c, 'Their household is credited.');
        }
    }

    @IsTest
    static void theJobComesFromTheShift() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact person = VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c driving = VolunteersTestData.job('Van driving');
            Volunteer_Shift__c shift = VolunteersTestData.shift(driving.Id);
            Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, jobId(), 3);
            hours.Volunteer_Shift__c = shift.Id;

            Test.startTest();
            insert hours;
            Test.stopTest();

            Assert.areEqual(
                driving.Id,
                reread(hours.Id).Volunteer_Job__c,
                'Hours on a shift carry that shift\'s job, so they keep it if the shift goes.'
            );
        }
    }

    @IsTest
    static void mergingTwoContactsMovesTheirApprovedHours() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Account household = VolunteersTestData.household('The Rivera Family');
            Contact survivor = VolunteersTestData.contact('Rivera', household.Id);
            Contact duplicate = VolunteersTestData.contact('Rivera', household.Id);
            Volunteer_Hours__c hours = VolunteersTestData.newHours(duplicate.Id, jobId(), 4);
            insert hours;
            VolunteerHoursService.approve(new Set<Id>{ hours.Id });

            Test.startTest();
            merge survivor duplicate;
            Test.stopTest();

            Volunteer_Hours__c saved = reread(hours.Id);
            Assert.areEqual(
                survivor.Id,
                saved.Contact__c,
                'The merge moves the hours to the surviving contact, past the approved lock.'
            );
            Assert.areEqual('Approved', saved.Status__c, 'And they stay approved.');
        }
    }

    @IsTest
    static void twoHundredFiftyOneEntriesSaveInOneGo() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Account household = VolunteersTestData.household('The Rivera Family');
            Contact person = VolunteersTestData.contact('Rivera', household.Id);
            Volunteer_Shift__c shift = VolunteersTestData.shift(jobId());
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            for (Integer i = 0; i < 251; i++) {
                Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, null, 1);
                hours.Volunteer_Shift__c = shift.Id;
                entries.add(hours);
            }

            Test.startTest();
            insert entries;
            Test.stopTest();

            Assert.areEqual(
                251,
                [
                    SELECT COUNT()
                    FROM Volunteer_Hours__c
                    WHERE
                        Household__c = :household.Id
                        AND Volunteer_Job__c = :jobId()
                        AND Status__c = 'Submitted'
                ],
                'Every entry has its household, its job and its starting status.'
            );
        }
    }
}
