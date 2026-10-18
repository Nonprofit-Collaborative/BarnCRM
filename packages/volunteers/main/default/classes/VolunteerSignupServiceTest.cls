/**
 * Sign-ups: one per person per shift (R-VU2), and marking attendance writes the hours once
 * (R-VU3).
 */
@IsTest(
    testFor='ApexClass:VolunteerSignupService, ApexClass:VolunteerSignupTriggerHandler, ApexClass:VolunteerIntegritySelector, ApexTrigger:VolunteerSignupTrigger'
)
private class VolunteerSignupServiceTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.shift(job.Id);
        }
    }

    private static Contact person() {
        return [SELECT Id FROM Contact LIMIT 1];
    }

    private static Volunteer_Shift__c theShift() {
        return [
            SELECT Id, Name, Volunteer_Job__c, Start_Time__c, End_Time__c
            FROM Volunteer_Shift__c
            LIMIT 1
        ];
    }

    private static String insertError(List<Volunteer_Signup__c> signups) {
        try {
            insert signups;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return '';
    }

    @IsTest
    static void aSecondSignupForTheSamePersonIsRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            Volunteer_Signup__c first = VolunteersTestData.newSignup(shift.Id, person().Id);
            first.Status__c = 'Cancelled';
            insert first;

            Test.startTest();
            String again = insertError(
                new List<Volunteer_Signup__c>{ VolunteersTestData.newSignup(shift.Id, person().Id) }
            );
            Test.stopTest();

            Assert.areEqual(
                String.format(
                    Label.Volunteers_Signup_AlreadySignedUp,
                    new List<String>{ shift.Name }
                ),
                again,
                'A cancelled booking still stands: the coordinator changes it rather than adding one.'
            );
        }
    }

    @IsTest
    static void twoSignupsForOnePersonInOneSaveAreRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();

            Test.startTest();
            String message = insertError(
                new List<Volunteer_Signup__c>{
                    VolunteersTestData.newSignup(shift.Id, person().Id),
                    VolunteersTestData.newSignup(shift.Id, person().Id)
                }
            );
            Test.stopTest();

            Assert.isTrue(message.contains(shift.Name), 'The refusal names the shift: ' + message);
            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Signup__c], 'Neither is saved.');
        }
    }

    @IsTest
    static void attendanceWritesTheHoursOnce() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            Volunteer_Signup__c signup = VolunteersTestData.newSignup(shift.Id, person().Id);
            insert signup;

            Test.startTest();
            update new Volunteer_Signup__c(Id = signup.Id, Status__c = 'Attended');
            update new Volunteer_Signup__c(Id = signup.Id, Status__c = 'No show');
            update new Volunteer_Signup__c(Id = signup.Id, Status__c = 'Attended');
            Test.stopTest();

            List<Volunteer_Hours__c> hours = [
                SELECT
                    Contact__c,
                    Volunteer_Shift__c,
                    Volunteer_Job__c,
                    Volunteer_Signup__c,
                    Date_Worked__c,
                    Hours__c,
                    Status__c
                FROM Volunteer_Hours__c
            ];
            Assert.areEqual(1, hours.size(), 'Marking attendance again writes no second entry.');
            Assert.areEqual(person().Id, hours[0].Contact__c, 'For the person.');
            Assert.areEqual(shift.Id, hours[0].Volunteer_Shift__c, 'Against the shift.');
            Assert.areEqual(shift.Volunteer_Job__c, hours[0].Volunteer_Job__c, 'And its job.');
            Assert.areEqual(signup.Id, hours[0].Volunteer_Signup__c, 'Naming the sign-up.');
            Assert.areEqual(shift.Start_Time__c.date(), hours[0].Date_Worked__c, 'On the day.');
            Assert.areEqual(3, hours[0].Hours__c, 'For the shift\'s length.');
            Assert.areEqual('Submitted', hours[0].Status__c, 'Waiting for a coordinator.');
        }
    }

    @IsTest
    static void attendanceHoursAreApprovedWhenApprovalIsOff() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.volunteerSettings(false, true);
            Volunteer_Signup__c signup = VolunteersTestData.newSignup(theShift().Id, person().Id);
            signup.Status__c = 'Attended';

            Test.startTest();
            insert signup;
            Test.stopTest();

            Assert.areEqual(
                'Approved',
                [SELECT Status__c FROM Volunteer_Hours__c].Status__c,
                'Hours written by attendance follow Hours Require Approval like any other.'
            );
        }
    }

    @IsTest
    static void noHoursWhenAttendanceCreatesHoursIsOff() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.volunteerSettings(true, false);
            Volunteer_Signup__c signup = VolunteersTestData.newSignup(theShift().Id, person().Id);
            signup.Status__c = 'Attended';

            Test.startTest();
            insert signup;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Hours__c],
                'The coordinator types them.'
            );
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountGetsTheirHours() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            Volunteer_Signup__c signup = new Volunteer_Signup__c(
                Volunteer_Shift__c = theShift().Id,
                Account__c = person.Id,
                Status__c = 'Attended'
            );

            Test.startTest();
            insert signup;
            Test.stopTest();

            Volunteer_Hours__c hours = [SELECT Contact__c, Account__c FROM Volunteer_Hours__c];
            Assert.areEqual(person.Id, hours.Account__c, 'The hours name the person account.');
            Assert.isNull(hours.Contact__c, 'And no contact.');
        }
    }

    @IsTest
    static void twoHundredFiftyOneAttendancesWriteTheirHours() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
            for (Contact volunteer : VolunteersTestData.contacts(251)) {
                signups.add(VolunteersTestData.newSignup(shift.Id, volunteer.Id));
            }
            insert signups;
            for (Volunteer_Signup__c signup : signups) {
                signup.Status__c = 'Attended';
            }

            Test.startTest();
            update signups;
            Test.stopTest();

            Assert.areEqual(
                251,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Volunteer_Shift__c = :shift.Id],
                'One entry per attended sign-up.'
            );
        }
    }

    @IsTest
    static void restoringASecondSignupIsRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            Volunteer_Signup__c first = VolunteersTestData.newSignup(shift.Id, person().Id);
            insert first;
            delete first;
            insert VolunteersTestData.newSignup(shift.Id, person().Id);
            String message = '';

            Test.startTest();
            try {
                undelete first;
            } catch (DmlException refused) {
                message = refused.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.isTrue(message.contains(shift.Name), 'R-VU2 holds on undelete: ' + message);
            Assert.areEqual(1, [SELECT COUNT() FROM Volunteer_Signup__c], 'One booking.');
        }
    }

    @IsTest
    static void restoringAnOldAttendanceEntryIsRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Signup__c signup = VolunteersTestData.newSignup(theShift().Id, person().Id);
            signup.Status__c = 'Attended';
            insert signup;
            Volunteer_Hours__c old = [SELECT Id FROM Volunteer_Hours__c];
            delete old;
            update new Volunteer_Signup__c(Id = signup.Id, Status__c = 'No show');
            update new Volunteer_Signup__c(Id = signup.Id, Status__c = 'Attended');
            String message = '';

            Test.startTest();
            try {
                undelete old;
            } catch (DmlException refused) {
                message = refused.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Volunteers_Hours_SecondEntryForSignup,
                message,
                'One attendance stays one entry (R-VU3).'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Volunteer_Hours__c], 'One entry.');
        }
    }

    @IsTest
    static void attendanceOnAShiftThatCannotBeReadIsLogged() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c gone = VolunteersTestData.shift(theShift().Volunteer_Job__c);
            Volunteer_Signup__c signup = VolunteersTestData.newSignup(theShift().Id, person().Id);
            insert signup;
            Id goneId = gone.Id;
            delete gone;
            Volunteer_Signup__c attended = new Volunteer_Signup__c(
                Id = signup.Id,
                Contact__c = person().Id,
                Volunteer_Shift__c = goneId,
                Status__c = 'Attended'
            );

            Test.startTest();
            VolunteerSignupService.createHoursForAttendance(
                new List<Volunteer_Signup__c>{ attended },
                null
            );
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Hours__c], 'No hours to write.');
            Integer naming = 0;
            for (Error_Log__c entry : [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Severity__c = 'Warning'
            ]) {
                if (entry.Message__c.contains(String.valueOf(signup.Id))) {
                    naming++;
                }
            }
            Assert.areEqual(
                1,
                naming,
                'A Warning names the sign-up, so the hours are typed by hand.'
            );
        }
    }
}
