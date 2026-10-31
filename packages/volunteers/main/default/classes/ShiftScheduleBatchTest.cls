/**
 * The nightly run at scale (R-SSC3, R-SSC6), the nightly job Health Check schedules, and the
 * hand over from a large save to the batch. These tests use the real clock and the org's own
 * time zone, so they also prove the org time zone is read.
 */
@IsTest(
    testFor='ApexClass:ShiftScheduleBatch, ApexClass:VolunteersScheduler, ApexClass:VolunteersNightlyJobProvider, ApexClass:ShiftScheduleGenerator, ApexClass:ShiftScheduleSelector'
)
private class ShiftScheduleBatchTest {
    private static final String RULES = 'Shift_Schedule_Rules';
    private static final List<String> WEEKDAYS = new List<String>{
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
    };

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.job('Food pantry sort');
        }
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    /** Tomorrow in the org's time zone, so no shift has started by the time a test runs. */
    private static Date tomorrow() {
        return ShiftScheduleService.today().addDays(1);
    }

    private static String weekdayOf(Date day) {
        return WEEKDAYS[Math.mod(Date.newInstance(1900, 1, 1).daysBetween(day), 7)];
    }

    /** Saves schedules without the save's own run, as the nightly run would find them. */
    private static List<Shift_Schedule__c> saved(Integer howMany, String chosenDays) {
        Id job = jobId();
        Date firstDay = tomorrow();
        List<Shift_Schedule__c> schedules = new List<Shift_Schedule__c>();
        for (Integer i = 0; i < howMany; i++) {
            schedules.add(VolunteersTestData.newSchedule(job, chosenDays, firstDay));
        }
        AutomationControl.bypass(RULES);
        insert schedules;
        AutomationControl.clearBypass(RULES);
        return schedules;
    }

    @IsTest
    static void theNightlyRunFills251WeeklySchedules26WeeksOut() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(26);
            List<Shift_Schedule__c> schedules = saved(251, weekdayOf(tomorrow()));
            // A test runs one batch chunk only, so the chunk covers all 251.
            ShiftScheduleBatch.chunkSizeOverride = 251;

            Test.startTest();
            Id batchId = ShiftScheduleBatch.startNightly();
            Test.stopTest();

            Assert.isNotNull(batchId, 'The nightly run starts.');
            // Tomorrow and every week after it up to today plus 182 days: 26 shifts each.
            Assert.areEqual(
                251 * 26,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c IN :schedules],
                'Every schedule is filled to the 26 week horizon.'
            );
            Assert.areEqual(
                251,
                [
                    SELECT COUNT()
                    FROM Shift_Schedule__c
                    WHERE
                        Id IN :schedules
                        AND Created_Through__c = :ShiftScheduleService.today().addDays(182)
                ],
                'Each schedule records the horizon.'
            );
        }
    }

    @IsTest
    static void oneChunkOfTenDailySchedulesAtTheLongestHorizonFitsOneTransaction() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(26);
            List<Shift_Schedule__c> schedules = saved(
                ShiftScheduleBatch.CHUNK_SIZE,
                String.join(WEEKDAYS, ';')
            );

            Test.startTest();
            ShiftScheduleBatch.startNightly();
            Test.stopTest();

            Assert.areEqual(
                ShiftScheduleBatch.CHUNK_SIZE * 182,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c IN :schedules],
                'Ten schedules on every day for 26 weeks: the most one transaction is asked to create.'
            );
        }
    }

    @IsTest
    static void aSaveLargerThanAChunkHandsItsSchedulesToTheBatch() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(2);
            List<Shift_Schedule__c> schedules = saved(2, weekdayOf(tomorrow()));
            AutomationControl.bypass(RULES);
            update new Shift_Schedule__c(Id = schedules[1].Id, Active__c = false);
            AutomationControl.clearBypass(RULES);
            ShiftScheduleBatch.chunkSizeOverride = 1;

            Test.startTest();
            new ShiftScheduleGenerator(new Map<Id, Shift_Schedule__c>(schedules).keySet())
                .execute(null);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :schedules[0].Id],
                'Two schedules are more than a chunk of one, so the batch ran the active one.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :schedules[1].Id],
                'The inactive one creates nothing.'
            );
        }
    }

    @IsTest
    static void healthCheckCanScheduleTheNightlyJob() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersScheduler.jobNameInUse = 'BarnCRM Volunteer Schedules test';
            List<NightlyJob> jobs = new VolunteersNightlyJobProvider().nightlyJobs();
            Boolean before = jobs[0].isScheduled();

            Test.startTest();
            jobs[0].schedule();
            jobs[0].schedule();
            Test.stopTest();

            Assert.areEqual(2, jobs.size(), 'The schedule run and the reminder run.');
            Assert.areEqual(
                Label.Volunteers_NightlyJobs_SchedulesName,
                jobs[0].label(),
                'Its label.'
            );
            Assert.isFalse(before, 'Not scheduled at first.');
            Assert.isTrue(
                jobs[0].isScheduled(),
                'Scheduled by the fix, once however often it is asked.'
            );
        }
    }

    @IsTest
    static void theNightlyJobRunsTheBatchAndSkipsWhileTheModuleIsOff() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.shiftHorizonWeeks(1);
            List<Shift_Schedule__c> schedules = saved(1, weekdayOf(tomorrow()));

            Test.startTest();
            new VolunteersScheduler().execute(null);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c = :schedules[0].Id],
                'The nightly job ran the batch: tomorrow is within a week.'
            );

            BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
            settings.Modules_Turned_Off__c = ShiftScheduleService.MODULE_NAME;
            TestDataFactory.saveSettings(settings);
            new VolunteersScheduler().execute(null);
            Assert.isTrue(
                ShiftScheduleService.isTurnedOff(),
                'Off, so the job only logs that it skipped.'
            );
            Assert.isNull(ShiftScheduleBatch.startNightly(), 'And the batch does not start.');
        }
    }
}
