/**
 * What saving, editing, ending and deleting a schedule does to its shifts (R-SSC3 to R-SSC5).
 * The saves are made by Standard Users holding only the BarnCRM Staff set and one Volunteers
 * set, so the Coordinator and Staff, who delete no shift, really lack delete; the checks are
 * read as an administrator. The clock and time zone are fixed as in ShiftScheduleServiceTest.
 *
 * Every test starts from one weekly Saturday schedule made on Friday 20 February 2026 with a
 * six week horizon (shifts on 21 and 28 February and 7, 14, 21 and 28 March), then moves the
 * clock to Monday 2 March, so two shifts are past; 7 March has a sign-up and 14 March is
 * Cancelled.
 */
@IsTest(
    testFor='ApexClass:ShiftScheduleTriggerHandler, ApexClass:ShiftScheduleGenerator, ApexClass:ShiftScheduleService, ApexTrigger:ShiftScheduleTrigger'
)
private class ShiftScheduleTriggerHandlerTest {
    private static final String ZONE = 'America/New_York';
    private static final String RULES = 'Shift_Schedule_Rules';
    private static final Datetime FRIDAY_NOON = Datetime.newInstanceGmt(2026, 2, 20, 17, 0, 0);
    private static final Datetime MONDAY_NOON = Datetime.newInstanceGmt(2026, 3, 2, 17, 0, 0);
    private static final String COORDINATOR = 'ScheduleCoordinator';
    private static final String STAFF = 'ScheduleStaff';
    private static final String READ_ONLY = 'ScheduleReader';

    @TestSetup
    static void makeData() {
        TestUsers.standardUserWith(
            COORDINATOR,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
        );
        TestUsers.standardUserWith(
            STAFF,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
        );
        TestUsers.standardUserWith(
            READ_ONLY,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Read_Only' }
        );
        System.runAs(admin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.shiftHorizonWeeks(6);
            ShiftScheduleService.timeZoneOverride = ZONE;
            ShiftScheduleService.nowOverride = FRIDAY_NOON;
            Shift_Schedule__c schedule = VolunteersTestData.newSchedule(
                job.Id,
                'Saturday',
                Date.newInstance(2026, 2, 21)
            );
            AutomationControl.bypass(RULES);
            insert schedule;
            AutomationControl.clearBypass(RULES);
            ShiftScheduleService.run(new Set<Id>{ schedule.Id });
            List<Volunteer_Shift__c> shifts = shiftsOf(schedule.Id);
            insert VolunteersTestData.newSignup(shifts[2].Id, contactId());
            update new Volunteer_Shift__c(Id = shifts[3].Id, Status__c = 'Cancelled');
        }
    }

    private static User admin() {
        return TestUsers.adminWith(VolunteersTestData.ADMIN);
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Id contactId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Rivera' LIMIT 1].Id;
    }

    private static Shift_Schedule__c schedule() {
        return [
            SELECT Id, Job__c, Created_Through__c, Shifts_Kept__c, Active__c
            FROM Shift_Schedule__c
            ORDER BY CreatedDate
            LIMIT 1
        ];
    }

    private static List<Volunteer_Shift__c> shiftsOf(Id scheduleId) {
        return [
            SELECT Id, Start_Time__c, Status__c, Shift_Schedule__c
            FROM Volunteer_Shift__c
            WHERE Shift_Schedule__c = :scheduleId
            ORDER BY Start_Time__c
        ];
    }

    private static Set<Id> idsOf(List<Volunteer_Shift__c> shifts) {
        return new Map<Id, Volunteer_Shift__c>(shifts).keySet();
    }

    private static void useMondayClock() {
        ShiftScheduleService.timeZoneOverride = ZONE;
        ShiftScheduleService.nowOverride = MONDAY_NOON;
    }

    private static void assertOneShiftADay(List<Volunteer_Shift__c> shifts) {
        Set<Date> found = new Set<Date>();
        for (Volunteer_Shift__c shift : shifts) {
            Assert.isTrue(
                found.add(ShiftScheduleService.orgDate(shift.Start_Time__c)),
                'No day holds two shifts of one schedule.'
            );
        }
    }

    @IsTest
    static void aStaffSaveCreatesTheShiftsAtOnce() {
        System.runAs(admin()) {
            useMondayClock();
            Shift_Schedule__c fresh = VolunteersTestData.newSchedule(
                schedule().Job__c,
                'Wednesday',
                Date.newInstance(2026, 3, 4)
            );

            Test.startTest();
            System.runAs(user(STAFF)) {
                insert fresh;
            }
            Test.stopTest();

            Assert.areEqual(
                6,
                shiftsOf(fresh.Id).size(),
                'Six Wednesdays from 4 March to the six week horizon, created by the queued run.'
            );
            Assert.areEqual(
                Date.newInstance(2026, 4, 13),
                [SELECT Created_Through__c FROM Shift_Schedule__c WHERE Id = :fresh.Id]
                .Created_Through__c,
                'Created Through moves to the horizon although Staff cannot edit it.'
            );
        }
    }

    @IsTest
    static void aReadOnlyUserCannotCreateASchedule() {
        System.runAs(admin()) {
            Shift_Schedule__c fresh = VolunteersTestData.newSchedule(
                schedule().Job__c,
                'Monday',
                Date.newInstance(2026, 3, 2)
            );
            Boolean refused = false;

            Test.startTest();
            System.runAs(user(READ_ONLY)) {
                try {
                    insert fresh;
                } catch (Exception expected) {
                    refused = true;
                }
            }
            Test.stopTest();

            Assert.isTrue(refused, 'Read Only reads schedules and creates none.');
        }
    }

    @IsTest
    static void editingThePatternReplacesOnlyUnbookedFutureShifts() {
        System.runAs(admin()) {
            useMondayClock();
            Shift_Schedule__c before = schedule();
            Set<Id> original = idsOf(shiftsOf(before.Id));

            Test.startTest();
            System.runAs(user(COORDINATOR)) {
                update new Shift_Schedule__c(
                    Id = before.Id,
                    Start_Time__c = Time.newInstance(10, 0, 0, 0)
                );
            }
            Test.stopTest();

            List<Volunteer_Shift__c> shifts = shiftsOf(before.Id);
            Assert.areEqual(
                2,
                schedule().Shifts_Kept__c,
                'The booked and the cancelled shift were kept.'
            );
            Assert.areEqual(
                8,
                shifts.size(),
                'Two past, two kept, and four recreated to the horizon.'
            );
            assertOneShiftADay(shifts);
            for (Integer i = 0; i < 4; i++) {
                Assert.isTrue(
                    original.contains(shifts[i].Id),
                    'Past, booked and cancelled shifts are the same records.'
                );
            }
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 3, 7, 14, 0, 0),
                shifts[2].Start_Time__c,
                'The booked shift keeps its 9:00 start.'
            );
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 3, 21, 14, 0, 0),
                shifts[4].Start_Time__c,
                'The recreated shift starts at the new 10:00, in summer time.'
            );
            Assert.isFalse(original.contains(shifts[4].Id), 'It is a new record.');
        }
    }

    @IsTest
    static void aNameOnlyChangeTouchesNoShift() {
        System.runAs(admin()) {
            useMondayClock();
            Shift_Schedule__c before = schedule();
            Set<Id> original = idsOf(shiftsOf(before.Id));

            Test.startTest();
            System.runAs(user(COORDINATOR)) {
                update new Shift_Schedule__c(Id = before.Id, Name = 'Saturday morning sort');
            }
            Test.stopTest();

            Assert.areEqual(original, idsOf(shiftsOf(before.Id)), 'The same shifts.');
            Assert.isNull(schedule().Shifts_Kept__c, 'Nothing was removed, so nothing is counted.');
            Assert.areEqual(
                before.Created_Through__c,
                schedule().Created_Through__c,
                'Created Through is kept.'
            );
        }
    }

    @IsTest
    static void endingRemovesUnbookedFutureShiftsAndTurningBackOnRefills() {
        System.runAs(admin()) {
            useMondayClock();
            Shift_Schedule__c before = schedule();

            System.runAs(user(STAFF)) {
                update new Shift_Schedule__c(Id = before.Id, Active__c = false);
            }
            Integer afterEnding = shiftsOf(before.Id).size();
            Shift_Schedule__c ended = schedule();

            Test.startTest();
            System.runAs(user(STAFF)) {
                update new Shift_Schedule__c(Id = before.Id, Active__c = true);
            }
            Test.stopTest();

            Assert.areEqual(
                4,
                afterEnding,
                'Staff ended it: 21 and 28 March went, the past two and the kept two stay.'
            );
            Assert.areEqual(
                2,
                ended.Shifts_Kept__c,
                'The booked and the cancelled shift were kept.'
            );
            Assert.isNull(ended.Created_Through__c, 'Created Through is cleared.');
            Assert.areEqual(
                8,
                shiftsOf(before.Id).size(),
                'Turning it on fills the horizon again from today.'
            );
            Assert.areEqual(
                Date.newInstance(2026, 4, 13),
                schedule().Created_Through__c,
                'To the horizon.'
            );
        }
    }

    @IsTest
    static void anEarlierEndDateRemovesOnlyTheShiftsAfterIt() {
        System.runAs(admin()) {
            useMondayClock();
            Shift_Schedule__c before = schedule();
            List<Volunteer_Shift__c> original = shiftsOf(before.Id);
            insert VolunteersTestData.newSignup(original[5].Id, contactId());

            Test.startTest();
            System.runAs(user(COORDINATOR)) {
                update new Shift_Schedule__c(
                    Id = before.Id,
                    End_Date__c = Date.newInstance(2026, 3, 20)
                );
            }
            Test.stopTest();

            Set<Id> left = idsOf(shiftsOf(before.Id));
            Assert.areEqual(5, left.size(), 'Only 21 March went.');
            Assert.isFalse(
                left.contains(original[4].Id),
                '21 March, after the new end, had no sign-up.'
            );
            Assert.isTrue(left.contains(original[5].Id), '28 March is kept: someone signed up.');
            Assert.areEqual(1, schedule().Shifts_Kept__c, 'One shift after the end was kept.');
        }
    }

    @IsTest
    static void deletingKeepsBookedShiftsWithoutTheirLink() {
        System.runAs(admin()) {
            useMondayClock();
            Shift_Schedule__c before = schedule();

            Test.startTest();
            delete new Shift_Schedule__c(Id = before.Id);
            Test.stopTest();

            List<Volunteer_Shift__c> left = [
                SELECT Id, Shift_Schedule__c
                FROM Volunteer_Shift__c
                WHERE Volunteer_Job__c = :before.Job__c
            ];
            Assert.areEqual(
                4,
                left.size(),
                'The two past shifts, the booked one and the cancelled one stay.'
            );
            for (Volunteer_Shift__c shift : left) {
                Assert.isNull(
                    shift.Shift_Schedule__c,
                    'A kept shift loses its link to the deleted schedule.'
                );
            }
        }
    }

    @IsTest
    static void aBulkSaveOf251SchedulesCreatesTheirShifts() {
        System.runAs(admin()) {
            useMondayClock();
            VolunteersTestData.shiftHorizonWeeks(2);
            Id jobId = schedule().Job__c;
            List<Shift_Schedule__c> many = new List<Shift_Schedule__c>();
            for (Integer i = 0; i < 251; i++) {
                many.add(
                    VolunteersTestData.newSchedule(jobId, 'Tuesday', Date.newInstance(2026, 3, 2))
                );
            }
            // A test runs one batch chunk only, so the queued run takes all 251 itself.
            ShiftScheduleBatch.chunkSizeOverride = 251;

            Test.startTest();
            System.runAs(user(COORDINATOR)) {
                insert many;
            }
            Test.stopTest();

            Assert.areEqual(
                502,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c IN :many],
                'Two Tuesdays for each of the 251 schedules, from one queued run as the coordinator.'
            );
        }
    }
}
