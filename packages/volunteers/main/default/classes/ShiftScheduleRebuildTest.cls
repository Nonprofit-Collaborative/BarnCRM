/**
 * Saves and deletes of 251 daily schedules (R-SSC4 to R-SSC6). At the longest horizon their
 * future shifts would be 45,682 rows, far over the 10,000 DML rows one transaction may write, so
 * a save removes shifts only for the schedules the transaction has rows for. An update marks the
 * rest Rebuild Pending, which the queued run, or the nightly run, finishes; a delete hands the
 * rest's shifts to ShiftScheduleRemovalJob by Id. The DML rows a test method uses in its setup
 * count against the method too, so a test cannot build the 10,000 shifts the real budget takes
 * to reach: the budget is set to 100 schedules instead, and its own arithmetic is checked apart.
 * The saves and deletes are made by Standard Users holding BarnCRM Staff and one Volunteers set.
 * These tests use the real clock and the org's own time zone.
 */
@IsTest(
    testFor='ApexClass:ShiftScheduleTriggerHandler, ApexClass:ShiftScheduleGenerator, ApexClass:ShiftScheduleBatch, ApexClass:ShiftScheduleService, ApexClass:ShiftScheduleSelector, ApexClass:ShiftScheduleRemovalJob'
)
private class ShiftScheduleRebuildTest {
    private static final String RULES = 'Shift_Schedule_Rules';
    private static final Integer SCHEDULE_COUNT = 251;
    private static final Integer HORIZON_WEEKS = 2;
    private static final Integer SHIFTS_EACH = 14;
    private static final Integer BUDGET = 100;
    private static final String EVERY_DAY = 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
    private static final String COORDINATOR = 'RebuildCoordinator';
    private static final String SCHEDULE_ADMIN = 'RebuildAdmin';

    @TestSetup
    static void makeData() {
        TestUsers.standardUserWith(
            COORDINATOR,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
        );
        TestUsers.standardUserWith(
            SCHEDULE_ADMIN,
            new List<String>{ VolunteersTestData.CORE_STAFF, VolunteersTestData.ADMIN }
        );
        System.runAs(admin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            Date firstDay = ShiftScheduleService.today().addDays(1);
            List<Shift_Schedule__c> created = new List<Shift_Schedule__c>();
            for (Integer i = 0; i < SCHEDULE_COUNT; i++) {
                created.add(VolunteersTestData.newSchedule(job.Id, EVERY_DAY, firstDay));
            }
            AutomationControl.bypass(RULES);
            insert created;
            AutomationControl.clearBypass(RULES);
            ShiftScheduleService.run(new Map<Id, Shift_Schedule__c>(created).keySet());
        }
    }

    private static User admin() {
        return TestUsers.adminWith(VolunteersTestData.ADMIN);
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static List<Shift_Schedule__c> allSchedules() {
        return [
            SELECT Id, Job__c, Created_Through__c, Shifts_Kept__c, Rebuild_Pending__c
            FROM Shift_Schedule__c
            WITH SYSTEM_MODE
            ORDER BY Id
        ];
    }

    private static List<Volunteer_Shift__c> shiftsOf(Id scheduleId) {
        return [
            SELECT Id, Start_Time__c
            FROM Volunteer_Shift__c
            WHERE Shift_Schedule__c = :scheduleId
            WITH SYSTEM_MODE
            ORDER BY Start_Time__c
        ];
    }

    private static void book(Id shiftId) {
        Id contactId = [SELECT Id FROM Contact WHERE LastName = 'Rivera' LIMIT 1].Id;
        insert VolunteersTestData.newSignup(shiftId, contactId);
    }

    @IsTest
    static void theInlineBudgetFollowsTheRowsLeftAndTheHorizon() {
        System.runAs(admin()) {
            VolunteersTestData.shiftHorizonWeeks(26);
            Integer atTheLongest = ShiftScheduleService.inlineScheduleBudget();
            VolunteersTestData.shiftHorizonWeeks(1);
            Integer atTheShortest = ShiftScheduleService.inlineScheduleBudget();

            Assert.isTrue(
                atTheLongest > 0 && atTheLongest * 182 < Limits.getLimitDmlRows(),
                'At 26 weeks a save removes shifts for some schedules, and their worst case fits.'
            );
            Assert.isTrue(
                atTheShortest > atTheLongest,
                'A shorter horizon leaves room for more schedules.'
            );
        }
    }

    @IsTest
    static void changingThePatternOf251DailySchedulesInOneSaveHitsNoLimit() {
        List<Shift_Schedule__c> all;
        Shift_Schedule__c last;
        System.runAs(admin()) {
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            all = allSchedules();
            last = all[SCHEDULE_COUNT - 1];
            Assert.areEqual(
                SCHEDULE_COUNT * SHIFTS_EACH,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c IN :all],
                'Every schedule is filled to the horizon before the change.'
            );
            book(shiftsOf(last.Id)[3].Id);
        }
        ShiftScheduleService.inlineBudgetOverride = BUDGET;
        ShiftScheduleBatch.chunkSizeOverride = SCHEDULE_COUNT;
        List<Shift_Schedule__c> changes = new List<Shift_Schedule__c>();
        for (Shift_Schedule__c schedule : all) {
            changes.add(new Shift_Schedule__c(Id = schedule.Id, Volunteers_Needed__c = 7));
        }

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            update changes;
        }
        Integer marked = [
            SELECT COUNT()
            FROM Shift_Schedule__c
            WHERE Rebuild_Pending__c = TRUE
            WITH SYSTEM_MODE
        ];
        Test.stopTest();

        System.runAs(admin()) {
            // The platform runs the trigger for 200 records, then 51, each with its own budget.
            Assert.areEqual(
                200 - BUDGET,
                marked,
                'Each trigger chunk marks the schedules beyond its budget Rebuild Pending.'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Volunteer_Shift__c
                    WHERE Shift_Schedule__c IN :all AND Volunteers_Needed__c = 4
                ],
                'Only the booked shift keeps the old number of places.'
            );
            Assert.areEqual(
                SCHEDULE_COUNT * SHIFTS_EACH - 1,
                [
                    SELECT COUNT()
                    FROM Volunteer_Shift__c
                    WHERE Shift_Schedule__c IN :all AND Volunteers_Needed__c = 7
                ],
                'Every other day is recreated from the new pattern, inline and by the queued run.'
            );
            for (Shift_Schedule__c schedule : allSchedules()) {
                Assert.areEqual(
                    schedule.Id == last.Id ? 1 : 0,
                    schedule.Shifts_Kept__c,
                    'Shifts Kept counts the booked shift only.'
                );
                Assert.isFalse(schedule.Rebuild_Pending__c, 'The run clears every mark.');
                Assert.isNotNull(schedule.Created_Through__c, 'Each schedule reaches the horizon.');
            }
        }
    }

    @IsTest
    static void theNightlyRunFinishesASaveWhoseRunWasNeverQueued() {
        System.runAs(admin()) {
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            List<Shift_Schedule__c> all = allSchedules();
            Shift_Schedule__c changed = all[0];
            Shift_Schedule__c ended = all[1];
            Shift_Schedule__c ending = all[2];
            Date endsOn = ShiftScheduleService.today().addDays(10);
            // As a save past its budget leaves them when no run could be queued: the pattern
            // changed, the schedule ended, and an earlier end date.
            AutomationControl.bypass(RULES);
            update new List<Shift_Schedule__c>{
                new Shift_Schedule__c(
                    Id = changed.Id,
                    Volunteers_Needed__c = 9,
                    Created_Through__c = null,
                    Rebuild_Pending__c = true
                ),
                new Shift_Schedule__c(
                    Id = ended.Id,
                    Active__c = false,
                    Created_Through__c = null,
                    Rebuild_Pending__c = true
                ),
                new Shift_Schedule__c(
                    Id = ending.Id,
                    End_Date__c = endsOn,
                    Created_Through__c = endsOn,
                    Rebuild_Pending__c = true
                )
            };
            AutomationControl.clearBypass(RULES);
            ShiftScheduleBatch.chunkSizeOverride = SCHEDULE_COUNT;

            Test.startTest();
            ShiftScheduleBatch.startNightly();
            Test.stopTest();

            Assert.areEqual(
                SHIFTS_EACH,
                [
                    SELECT COUNT()
                    FROM Volunteer_Shift__c
                    WHERE Shift_Schedule__c = :changed.Id AND Volunteers_Needed__c = 9
                ],
                'The changed schedule has a full horizon again, all from the new pattern.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :ended.Id],
                'The ended schedule, though inactive, lost every future shift and creates none.'
            );
            Assert.areEqual(
                10,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :ending.Id],
                'The schedule with an earlier end keeps the ten days through it.'
            );
            for (Shift_Schedule__c schedule : [
                SELECT Shifts_Kept__c, Rebuild_Pending__c
                FROM Shift_Schedule__c
                WHERE Id IN :new List<Id>{ changed.Id, ended.Id, ending.Id }
            ]) {
                Assert.areEqual(0, schedule.Shifts_Kept__c, 'The run records Shifts Kept.');
                Assert.isFalse(schedule.Rebuild_Pending__c, 'The run clears the mark.');
            }
        }
    }

    @IsTest
    static void deleting251SchedulesRemovesTheirShiftsInlineAndQueued() {
        List<Shift_Schedule__c> all;
        Id jobId;
        System.runAs(admin()) {
            all = allSchedules();
            jobId = all[0].Job__c;
            book(shiftsOf(all[0].Id)[2].Id);
            book(shiftsOf(all[SCHEDULE_COUNT - 1].Id)[5].Id);
        }
        ShiftScheduleService.inlineBudgetOverride = BUDGET;

        Test.startTest();
        System.runAs(user(SCHEDULE_ADMIN)) {
            delete all;
        }
        Integer leftAfterSave = [
            SELECT COUNT()
            FROM Volunteer_Shift__c
            WHERE Volunteer_Job__c = :jobId
            WITH SYSTEM_MODE
        ];
        Test.stopTest();

        System.runAs(admin()) {
            Assert.areEqual(
                1 + (SCHEDULE_COUNT - BUDGET) * SHIFTS_EACH,
                leftAfterSave,
                'The save removes the shifts of the schedules within its budget only.'
            );
            List<Volunteer_Shift__c> left = [
                SELECT Id, Shift_Schedule__c
                FROM Volunteer_Shift__c
                WHERE Volunteer_Job__c = :jobId
            ];
            Assert.areEqual(2, left.size(), 'Only the two booked shifts stay.');
            for (Volunteer_Shift__c shift : left) {
                Assert.isNull(shift.Shift_Schedule__c, 'A kept shift loses its link.');
            }
        }
    }

    @IsTest
    static void theQueuedRemovalKeepsAShiftBookedOrCancelledSinceTheSave() {
        System.runAs(admin()) {
            Id scheduleId = allSchedules()[0].Id;
            Set<Id> removable = ShiftScheduleService.removableFutureShiftIds(
                new Set<Id>{ scheduleId }
            );
            Assert.areEqual(SHIFTS_EACH, removable.size(), 'Every future shift is removable.');
            List<Volunteer_Shift__c> shifts = shiftsOf(scheduleId);
            book(shifts[0].Id);
            update new Volunteer_Shift__c(Id = shifts[1].Id, Status__c = 'Cancelled');

            Test.startTest();
            System.runAs(user(SCHEDULE_ADMIN)) {
                ShiftScheduleRemovalJob.queue(removable);
            }
            Test.stopTest();

            Assert.areEqual(
                2,
                shiftsOf(scheduleId).size(),
                'The shift booked and the shift cancelled after the Ids were taken stay.'
            );
        }
    }

    @IsTest
    static void aJobRemovesItsShareAndPassesTheRestOn() {
        System.runAs(admin()) {
            Id scheduleId = allSchedules()[0].Id;
            Set<Id> removable = ShiftScheduleService.removableFutureShiftIds(
                new Set<Id>{ scheduleId }
            );
            ShiftScheduleRemovalJob.shiftsPerJobOverride = 10;

            Test.startTest();
            System.runAs(user(SCHEDULE_ADMIN)) {
                ShiftScheduleRemovalJob.queue(removable);
            }
            Test.stopTest();

            // A test cannot run a chained job, so the next job's four shifts are still there.
            // The failed chain is logged, not thrown.
            Assert.areEqual(
                SHIFTS_EACH - 10,
                shiftsOf(scheduleId).size(),
                'The first job removes ten shifts and leaves the rest to the next.'
            );
        }
    }

    @IsTest
    static void aRemovalWithNoQueueableJobLeftIsLoggedNotThrown() {
        System.runAs(admin()) {
            Set<Id> removable = ShiftScheduleService.removableFutureShiftIds(
                new Set<Id>{ allSchedules()[0].Id }
            );

            Test.startTest();
            for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
                System.enqueueJob(new ShiftScheduleRemovalJob(new List<Id>()));
            }
            ShiftScheduleRemovalJob.queue(removable);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'ShiftScheduleRemovalJob'],
                'A removal that cannot be queued is logged.'
            );
        }
    }
}
