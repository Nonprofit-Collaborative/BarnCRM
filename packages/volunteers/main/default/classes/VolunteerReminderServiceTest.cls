/**
 * Shift reminders (V-10, R-VU6): who is emailed, once each, and who never is.
 *
 * The platform's email call is replaced by a stub that records the messages, so the tests prove
 * what would be sent without depending on the org's email deliverability setting.
 */
@IsTest(
    testFor='ApexClass:VolunteerReminderService, ApexClass:VolunteerReminderSelector, ApexClass:VolunteerReminderBatch, ApexClass:VolunteerReminderScheduler, ApexClass:VolunteersNightlyJobProvider, ApexClass:VolunteerSettings'
)
private class VolunteerReminderServiceTest {
    /** Records what it was given and says every message went out, or none. */
    private class StubSender implements VolunteerReminderService.ReminderSender {
        private final Boolean succeed;
        private final List<Messaging.SingleEmailMessage> got = new List<Messaging.SingleEmailMessage>();

        private StubSender(Boolean succeed) {
            this.succeed = succeed;
        }

        public List<Boolean> send(List<Messaging.SingleEmailMessage> messages) {
            got.addAll(messages);
            List<Boolean> outcome = new List<Boolean>();
            for (Messaging.SingleEmailMessage message : messages) {
                outcome.add(succeed);
            }
            return outcome;
        }
    }

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.job('Food pantry sort');
        }
    }

    private static void settings(Boolean enabled, Integer leadDays) {
        OrgSettingsSystemWriter.save(
            Volunteer_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Volunteer_Settings__c.Reminders_Enabled__c => enabled,
                Volunteer_Settings__c.Reminder_Lead_Days__c => leadDays
            }
        );
        SettingsService.clearCaches();
    }

    private static Contact person(String lastName, String email, Boolean optedOut) {
        Contact record = VolunteersTestData.contact(lastName, null);
        record.Email = email;
        record.HasOptedOutOfEmail = optedOut;
        update record;
        return record;
    }

    private static Volunteer_Shift__c shiftIn(Integer hoursAhead, String location) {
        Volunteer_Job__c job = [SELECT Id FROM Volunteer_Job__c LIMIT 1];
        Volunteer_Shift__c shift = VolunteersTestData.newShift(
            job.Id,
            ShiftScheduleService.now().addHours(hoursAhead),
            2
        );
        shift.Location__c = location;
        insert shift;
        return shift;
    }

    private static Volunteer_Signup__c book(Id shiftId, Contact person, String status) {
        Volunteer_Signup__c signup = VolunteersTestData.newSignup(shiftId, person.Id);
        signup.Status__c = status;
        insert signup;
        return signup;
    }

    /** What the morning run's chunk would be given. */
    private static List<Volunteer_Signup__c> due() {
        List<Volunteer_Signup__c> found = new List<Volunteer_Signup__c>();
        Datetime now = ShiftScheduleService.now();
        Datetime windowEnd = VolunteerReminderService.windowEnd(
            VolunteerSettings.reminderLeadDays()
        );
        for (Volunteer_Signup__c signup : [
            SELECT
                Id,
                Contact__c,
                Contact__r.FirstName,
                Contact__r.Email,
                Volunteer_Shift__r.Start_Time__c,
                Volunteer_Shift__r.End_Time__c,
                Volunteer_Shift__r.Location__c,
                Volunteer_Shift__r.Volunteer_Job__r.Name
            FROM Volunteer_Signup__c
            WHERE
                Reminder_Sent_On__c = NULL
                AND Status__c IN ('Signed up', 'Confirmed')
                AND Contact__r.Email != NULL
                AND Contact__r.HasOptedOutOfEmail = FALSE
                AND Volunteer_Shift__r.Status__c = 'Open'
                AND Volunteer_Shift__r.Start_Time__c > :now
                AND Volunteer_Shift__r.Start_Time__c < :windowEnd
            WITH SYSTEM_MODE
        ]) {
            found.add(signup);
        }
        return found;
    }

    private static List<Volunteer_Signup__c> stamped() {
        return [
            SELECT Id
            FROM Volunteer_Signup__c
            WHERE Reminder_Sent_On__c != NULL
            WITH SYSTEM_MODE
        ];
    }

    private static Integer runBatch() {
        Test.startTest();
        VolunteerReminderBatch.startMorning();
        Test.stopTest();
        return stamped().size();
    }

    @IsTest
    static void aDueBookingIsEmailedOnceAndStamped() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 1);
            Contact ana = person('Rivera', 'ana@example.org', false);
            book(shiftIn(3, 'Church hall').Id, ana, 'Signed up');

            Integer firstRun = runBatch();
            Integer secondRun = VolunteerReminderService.remind(due());

            Assert.areEqual(1, firstRun, 'The booking is stamped after its reminder.');
            Assert.areEqual(0, secondRun, 'Nothing is due on the second run.');
            Assert.areEqual(1, stub.got.size(), 'One email in two runs: one reminder per booking.');
            Messaging.SingleEmailMessage sent = stub.got[0];
            Assert.areEqual('ana@example.org', sent.getToAddresses()[0], 'To the Contact address.');
            Assert.isTrue(
                sent.getSubject().contains('Food pantry sort'),
                'The subject names the job.'
            );
            Assert.isTrue(
                sent.getPlainTextBody().startsWith('Hello Ana,'),
                'Greets by first name.'
            );
            Assert.isTrue(sent.getPlainTextBody().contains('Church hall'), 'Names the place.');
        }
    }

    @IsTest
    static void aConfirmedBookingIsRemindedToo() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 1);
            book(shiftIn(3, null).Id, person('Rivera', 'ana@example.org', false), 'Confirmed');

            runBatch();

            Assert.areEqual(1, stub.got.size(), 'Confirmed is reminded.');
            Assert.isFalse(
                stub.got[0].getPlainTextBody().contains('Where:'),
                'No place line when the shift has no location.'
            );
        }
    }

    @IsTest
    static void nobodyWhoShouldNotBeEmailedIsEmailed() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 1);
            Volunteer_Shift__c ahead = shiftIn(3, null);
            Volunteer_Shift__c later = shiftIn(24 * 6, null);
            Volunteer_Shift__c past = shiftIn(-3, null);
            Volunteer_Shift__c cancelled = shiftIn(4, null);
            cancelled.Status__c = 'Cancelled';
            update cancelled;
            book(ahead.Id, person('OptedOut', 'a@example.org', true), 'Signed up');
            book(ahead.Id, person('NoEmail', null, false), 'Signed up');
            book(ahead.Id, person('Dropped', 'b@example.org', false), 'Cancelled');
            book(ahead.Id, person('Absent', 'c@example.org', false), 'No show');
            book(later.Id, person('TooFar', 'd@example.org', false), 'Signed up');
            book(past.Id, person('Gone', 'e@example.org', false), 'Signed up');
            book(cancelled.Id, person('Called', 'f@example.org', false), 'Signed up');

            Integer stamps = runBatch();

            Assert.areEqual(0, stub.got.size(), 'No email for any of them.');
            Assert.areEqual(0, stamps, 'And none is stamped.');
        }
    }

    @IsTest
    static void aLongerLeadTimeReachesFurtherShifts() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 7);
            book(shiftIn(24 * 6, null).Id, person('Rivera', 'ana@example.org', false), 'Signed up');

            runBatch();

            Assert.areEqual(1, stub.got.size(), 'A shift six days out is inside a seven day lead.');
        }
    }

    @IsTest
    static void nothingRunsWhileRemindersAreOff() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            Contact ana = person('Rivera', 'ana@example.org', false);
            book(shiftIn(3, null).Id, ana, 'Signed up');

            Id started = VolunteerReminderBatch.startMorning();
            Integer sentDirectly = VolunteerReminderService.remind(due());

            Assert.isNull(started, 'No run starts by default: the setting ships off.');
            Assert.areEqual(0, sentDirectly, 'The service sends nothing either.');
            Assert.areEqual(0, stub.got.size(), 'No email.');
            Assert.isFalse(VolunteerSettings.remindersEnabled(), 'Off until turned on.');
        }
    }

    @IsTest
    static void aFailedSendIsNotStampedAndIsLogged() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteerReminderService.senderInUse = new StubSender(false);
            settings(true, 1);
            book(shiftIn(3, null).Id, person('Rivera', 'ana@example.org', false), 'Signed up');

            Integer stamps = runBatch();

            Assert.areEqual(0, stamps, 'Not stamped, so tomorrow tries again.');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'VolunteerReminderService'
                    WITH SYSTEM_MODE
                ],
                'The failure is in the Error Log.'
            );
        }
    }

    @IsTest
    static void clearingTheStampSendsTheReminderAgain() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 1);
            Volunteer_Signup__c signup = book(
                shiftIn(3, null).Id,
                person('Rivera', 'ana@example.org', false),
                'Signed up'
            );
            runBatch();

            update new Volunteer_Signup__c(Id = signup.Id, Reminder_Sent_On__c = null);
            VolunteerReminderService.remind(due());

            Assert.areEqual(2, stub.got.size(), 'A coordinator can send it again.');
        }
    }

    @IsTest
    static void aBookingWithoutAFirstNameIsGreetedPlainly() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 1);
            Contact nameless = person('Rivera', 'ana@example.org', false);
            nameless.FirstName = null;
            update nameless;
            book(shiftIn(3, null).Id, nameless, 'Signed up');

            runBatch();

            Assert.isTrue(
                stub.got[0].getPlainTextBody().startsWith('Hello,'),
                'No name, no "null".'
            );
        }
    }

    @IsTest
    static void leadDaysReadAsTheShippedValueWhenBlankOrOutOfRange() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(1, VolunteerSettings.reminderLeadDays(), 'Never saved: one day.');
            settings(true, 99);
            Assert.areEqual(1, VolunteerSettings.reminderLeadDays(), 'Out of range: one day.');
            settings(true, 14);
            Assert.areEqual(14, VolunteerSettings.reminderLeadDays(), 'The top of the range.');
        }
    }

    @IsTest
    static void theMorningJobIsSchedulableOnceAndRuns() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteerReminderScheduler.jobNameInUse = 'BarnCRM Volunteer Reminders test';
            StubSender stub = new StubSender(true);
            VolunteerReminderService.senderInUse = stub;
            settings(true, 1);
            book(shiftIn(3, null).Id, person('Rivera', 'ana@example.org', false), 'Signed up');
            List<NightlyJob> jobs = new VolunteersNightlyJobProvider().nightlyJobs();
            Boolean before = jobs[1].isScheduled();

            Test.startTest();
            jobs[1].schedule();
            jobs[1].schedule();
            new VolunteerReminderScheduler().execute(null);
            Test.stopTest();

            Assert.isFalse(before, 'Not scheduled at first.');
            Assert.isTrue(jobs[1].isScheduled(), 'Scheduled, once however often asked.');
            Assert.areEqual(
                Label.Volunteers_NightlyJobs_RemindersName,
                jobs[1].label(),
                'Its label.'
            );
            Assert.areEqual(1, stub.got.size(), 'The job ran the reminders.');
        }
    }
}
