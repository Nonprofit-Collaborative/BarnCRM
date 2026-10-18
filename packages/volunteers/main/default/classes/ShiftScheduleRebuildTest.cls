/**
 * A save that changes the pattern of 251 daily schedules at a six week horizon (R-SSC4, R-SSC6):
 * their future shifts are 10,542 rows, more than the 10,000 DML rows one transaction may write,
 * so the save removes shifts only for the schedules the transaction has rows for and hands the
 * rest to ShiftScheduleBatch. These tests use the real clock and the org's own time zone.
 */
@IsTest(
    testFor='ApexClass:ShiftScheduleTriggerHandler, ApexClass:ShiftScheduleGenerator, ApexClass:ShiftScheduleBatch, ApexClass:ShiftScheduleService, ApexClass:ShiftScheduleSelector'
)
private class ShiftScheduleRebuildTest {
    private static final String RULES = 'Shift_Schedule_Rules';
    private static final Integer SCHEDULE_COUNT = 251;
    private static final Integer HORIZON_WEEKS = 6;
    private static final Integer SHIFTS_EACH = 42;
    private static final String EVERY_DAY = 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            Date firstDay = ShiftScheduleService.today().addDays(1);
            List<Shift_Schedule__c> schedules = new List<Shift_Schedule__c>();
            for (Integer i = 0; i < SCHEDULE_COUNT; i++) {
                schedules.add(VolunteersTestData.newSchedule(job.Id, EVERY_DAY, firstDay));
            }
            AutomationControl.bypass(RULES);
            insert schedules;
            AutomationControl.clearBypass(RULES);
            // Half of the shifts here and half in the test, so no transaction writes over 10,000.
            ShiftScheduleService.run(firstHalf(schedules));
        }
    }

    private static Set<Id> firstHalf(List<Shift_Schedule__c> schedules) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 0; i < SCHEDULE_COUNT / 2; i++) {
            ids.add(schedules[i].Id);
        }
        return ids;
    }

    private static List<Shift_Schedule__c> schedules() {
        return [SELECT Id, Created_Through__c, Shifts_Kept__c FROM Shift_Schedule__c ORDER BY Id];
    }

    @IsTest
    static void changingThePatternOf251DailySchedulesInOneSaveHitsNoLimit() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(HORIZON_WEEKS);
            List<Shift_Schedule__c> all = schedules();
            Set<Id> fresh = new Set<Id>();
            for (Shift_Schedule__c schedule : all) {
                fresh.add(schedule.Id);
            }
            fresh.removeAll(firstHalf(all));
            ShiftScheduleService.run(fresh);
            Assert.areEqual(
                SCHEDULE_COUNT * SHIFTS_EACH,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c IN :all],
                'Every schedule is filled to the horizon before the change.'
            );
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
                'Every schedule is recreated to the horizon from the new pattern, inline or by the batch.'
            );
            for (Shift_Schedule__c schedule : schedules()) {
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
            List<Shift_Schedule__c> all = schedules();
            Shift_Schedule__c changed = all[0];
            Shift_Schedule__c ended = all[1];
            Shift_Schedule__c ending = all[2];
            // The batch is handed these as a save would: the pattern changed, the schedule ended,
            // and an earlier end date.
            AutomationControl.bypass(RULES);
            update new List<Shift_Schedule__c>{
                new Shift_Schedule__c(Id = changed.Id, Volunteers_Needed__c = 9),
                new Shift_Schedule__c(Id = ended.Id, Active__c = false),
                new Shift_Schedule__c(
                    Id = ending.Id,
                    End_Date__c = ShiftScheduleService.today().addDays(10)
                )
            };
            AutomationControl.clearBypass(RULES);
            Map<Id, Date> keepThrough = new Map<Id, Date>{
                changed.Id => null,
                ended.Id => null,
                ending.Id => ShiftScheduleService.today().addDays(10)
            };
            ShiftScheduleBatch.chunkSizeOverride = 3;

            Test.startTest();
            ShiftScheduleGenerator.queueRebuild(keepThrough);
            Test.stopTest();

            Assert.areEqual(
                SHIFTS_EACH,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :changed.Id],
                'The changed schedule has a full horizon again.'
            );
            Assert.areEqual(
                SHIFTS_EACH,
                [
                    SELECT COUNT()
                    FROM Volunteer_Shift__c
                    WHERE Shift_Schedule__c = :changed.Id AND Volunteers_Needed__c = 9
                ],
                'All from the new pattern.'
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
