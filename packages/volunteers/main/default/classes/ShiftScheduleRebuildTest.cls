/**
 * A save that changes the pattern of 251 daily schedules (R-SSC4, R-SSC6). At the longest
 * horizon their future shifts would be 45,682 rows, far over the 10,000 DML rows one transaction
 * may write, so the save removes shifts only for the schedules the transaction has rows for and
 * hands the rest to ShiftScheduleBatch. The DML rows a test method uses in its setup count
 * against the method too, so a test cannot build the 10,000 shifts the real budget takes to
 * reach: the budget is set to 100 schedules instead, and its own arithmetic is checked apart.
 * These tests use the real clock and the org's own time zone.
 */
@IsTest(
    testFor='ApexClass:ShiftScheduleTriggerHandler, ApexClass:ShiftScheduleGenerator, ApexClass:ShiftScheduleBatch, ApexClass:ShiftScheduleService, ApexClass:ShiftScheduleSelector'
)
private class ShiftScheduleRebuildTest {
    private static final String RULES = 'Shift_Schedule_Rules';
    private static final Integer SCHEDULE_COUNT = 251;
    private static final Integer HORIZON_WEEKS = 2;
    private static final Integer SHIFTS_EACH = 14;
    private static final String EVERY_DAY = 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
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

    private static List<Shift_Schedule__c> allSchedules() {
        return [SELECT Id, Created_Through__c, Shifts_Kept__c FROM Shift_Schedule__c ORDER BY Id];
    }

    @IsTest
    static void theInlineBudgetFollowsTheRowsLeftAndTheHorizon() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
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
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            List<Shift_Schedule__c> all = allSchedules();
            Assert.areEqual(
                SCHEDULE_COUNT * SHIFTS_EACH,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c IN :all],
                'Every schedule is filled to the horizon before the change.'
            );
            ShiftScheduleService.inlineBudgetOverride = 100;
            ShiftScheduleBatch.chunkSizeOverride = SCHEDULE_COUNT;
            for (Shift_Schedule__c schedule : all) {
                schedule.Volunteers_Needed__c = 7;
            }

            Test.startTest();
            update all;
            Test.stopTest();

            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Volunteer_Shift__c
                    WHERE Shift_Schedule__c IN :all AND Volunteers_Needed__c = 4
                ],
                'No shift is left with the old number of places.'
            );
            Assert.areEqual(
                SCHEDULE_COUNT * SHIFTS_EACH,
                [
                    SELECT COUNT()
                    FROM Volunteer_Shift__c
                    WHERE Shift_Schedule__c IN :all AND Volunteers_Needed__c = 7
                ],
                'Every schedule is recreated from the new pattern, 100 inline and the rest by the batch.'
            );
            for (Shift_Schedule__c schedule : allSchedules()) {
                Assert.areEqual(
                    0,
                    schedule.Shifts_Kept__c,
                    'Nothing was booked, so none was kept.'
                );
                Assert.isNotNull(schedule.Created_Through__c, 'Each schedule reaches the horizon.');
            }
        }
    }

    @IsTest
    static void theRebuildRemovesRecreatesAndRecordsAChunk() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            List<Shift_Schedule__c> all = allSchedules();
            Shift_Schedule__c changed = all[0];
            Shift_Schedule__c ended = all[1];
            Shift_Schedule__c ending = all[2];
            Date endsOn = ShiftScheduleService.today().addDays(10);
            // The batch is handed these as a save would: the pattern changed, the schedule ended,
            // and an earlier end date.
            AutomationControl.bypass(RULES);
            update new List<Shift_Schedule__c>{
                new Shift_Schedule__c(Id = changed.Id, Volunteers_Needed__c = 9),
                new Shift_Schedule__c(Id = ended.Id, Active__c = false),
                new Shift_Schedule__c(Id = ending.Id, End_Date__c = endsOn)
            };
            AutomationControl.clearBypass(RULES);
            Map<Id, Date> keepThrough = new Map<Id, Date>{
                changed.Id => null,
                ended.Id => null,
                ending.Id => endsOn
            };
            ShiftScheduleBatch.chunkSizeOverride = 3;

            Test.startTest();
            ShiftScheduleGenerator.queueRebuild(keepThrough);
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
                'The ended schedule lost every future shift and creates none.'
            );
            Assert.areEqual(
                10,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :ending.Id],
                'The schedule with an earlier end keeps the ten days through it.'
            );
            for (Shift_Schedule__c schedule : [
                SELECT Shifts_Kept__c
                FROM Shift_Schedule__c
                WHERE Id IN :keepThrough.keySet()
            ]) {
                Assert.areEqual(0, schedule.Shifts_Kept__c, 'The batch records Shifts Kept.');
            }
        }
    }
}
