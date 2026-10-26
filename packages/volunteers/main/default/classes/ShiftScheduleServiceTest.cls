/**
 * Which days a schedule falls on (R-SSC1), the run that creates them up to the horizon (R-SSC2)
 * and its idempotency, a horizon change, an end date and daylight saving. The clock and the
 * time zone are fixed (America/New_York, Monday 2 March 2026 at noon), so no test depends on
 * the day it runs or the org's time zone.
 */
@IsTest(
    testFor='ApexClass:ShiftScheduleService, ApexClass:ShiftScheduleSelector, ApexClass:VolunteerSettings'
)
private class ShiftScheduleServiceTest {
    private static final String ZONE = 'America/New_York';
    private static final String RULES = 'Shift_Schedule_Rules';
    /** Monday 2 March 2026, 12:00 in New York: before the change to summer time on 8 March. */
    private static final Datetime MONDAY_NOON = Datetime.newInstanceGmt(2026, 3, 2, 17, 0, 0);
    private static final Time NINE = Time.newInstance(9, 0, 0, 0);

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.job('Food pantry sort');
        }
    }

    private static void useClock(Datetime now) {
        ShiftScheduleService.timeZoneOverride = ZONE;
        ShiftScheduleService.nowOverride = now;
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    /** Saves a schedule without the save's own run, so each test runs it when it chooses. */
    private static Shift_Schedule__c saved(String weekdays, Date startDate, Date endDate) {
        Shift_Schedule__c schedule = VolunteersTestData.newSchedule(jobId(), weekdays, startDate);
        schedule.End_Date__c = endDate;
        AutomationControl.bypass(RULES);
        insert schedule;
        AutomationControl.clearBypass(RULES);
        return schedule;
    }

    private static List<Volunteer_Shift__c> shiftsOf(Id scheduleId) {
        return [
            SELECT Id, Name, Start_Time__c, End_Time__c, Status__c, Volunteers_Needed__c
            FROM Volunteer_Shift__c
            WHERE Shift_Schedule__c = :scheduleId
            WITH SYSTEM_MODE
            ORDER BY Start_Time__c
        ];
    }

    private static Date createdThrough(Id scheduleId) {
        return [
            SELECT Created_Through__c
            FROM Shift_Schedule__c
            WHERE Id = :scheduleId
            WITH SYSTEM_MODE
        ]
        .Created_Through__c;
    }

    private static Integer run(Id scheduleId) {
        return ShiftScheduleService.run(new Set<Id>{ scheduleId });
    }

    @IsTest
    static void everyOtherWeekCountsFromTheWeekOfTheStartDate() {
        // runs-as: deploying user (pure logic: works out dates in memory, no DML or SOQL)
        Shift_Schedule__c schedule = new Shift_Schedule__c(
            Weekdays__c = 'Tuesday;Thursday',
            Every_N_Weeks__c = 2,
            Start_Date__c = Date.newInstance(2026, 3, 4)
        );

        List<Date> days = ShiftScheduleService.shiftDays(
            schedule,
            Date.newInstance(2026, 3, 2),
            Date.newInstance(2026, 3, 29)
        );
        schedule.End_Date__c = Date.newInstance(2026, 3, 18);
        List<Date> ended = ShiftScheduleService.shiftDays(
            schedule,
            Date.newInstance(2026, 3, 2),
            Date.newInstance(2026, 3, 29)
        );

        Assert.areEqual(
            new List<Date>{
                Date.newInstance(2026, 3, 5),
                Date.newInstance(2026, 3, 17),
                Date.newInstance(2026, 3, 19)
            },
            days,
            'The start week counts as week one, the Tuesday before the start date is not a shift day, and the next week is skipped.'
        );
        Assert.areEqual(
            new List<Date>{ Date.newInstance(2026, 3, 5), Date.newInstance(2026, 3, 17) },
            ended,
            'Nothing after the end date.'
        );
    }

    @IsTest
    static void nineOClockStaysNineAcrossDaylightSaving() {
        // runs-as: deploying user (pure logic: converts times in memory, no DML or SOQL)
        useClock(MONDAY_NOON);

        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 3, 7, 14, 0, 0),
            ShiftScheduleService.toOrgDatetime(Date.newInstance(2026, 3, 7), NINE),
            'Saturday before the spring change: 9:00 EST is 14:00 GMT.'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 3, 8, 13, 0, 0),
            ShiftScheduleService.toOrgDatetime(Date.newInstance(2026, 3, 8), NINE),
            'The day of the spring change: 9:00 EDT is 13:00 GMT.'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 10, 31, 13, 0, 0),
            ShiftScheduleService.toOrgDatetime(Date.newInstance(2026, 10, 31), NINE),
            'Saturday before the autumn change: 9:00 EDT.'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 11, 1, 14, 0, 0),
            ShiftScheduleService.toOrgDatetime(Date.newInstance(2026, 11, 1), NINE),
            'The day of the autumn change: 9:00 EST.'
        );
        Assert.isNotNull(
            ShiftScheduleService.toOrgDatetime(
                Date.newInstance(2026, 3, 8),
                Time.newInstance(2, 30, 0, 0)
            ),
            'A time the clocks skip still gives a start.'
        );
    }

    @IsTest
    static void aRunFillsTheHorizonAcrossADaylightSavingChange() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            useClock(MONDAY_NOON);
            VolunteersTestData.shiftHorizonWeeks(2);
            Shift_Schedule__c schedule = saved(
                'Saturday;Sunday',
                Date.newInstance(2026, 2, 28),
                null
            );

            Test.startTest();
            Integer created = run(schedule.Id);
            Test.stopTest();

            List<Volunteer_Shift__c> shifts = shiftsOf(schedule.Id);
            Assert.areEqual(4, created, 'Saturdays and Sundays from today to two weeks ahead.');
            Assert.areEqual(4, shifts.size(), 'Four shifts saved.');
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 3, 7, 14, 0, 0),
                shifts[0].Start_Time__c,
                '9:00 EST.'
            );
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 3, 7, 17, 0, 0),
                shifts[0].End_Time__c,
                '12:00 EST.'
            );
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 3, 8, 13, 0, 0),
                shifts[1].Start_Time__c,
                '9:00 EDT after the change.'
            );
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 3, 15, 13, 0, 0),
                shifts[3].Start_Time__c,
                'Still 9:00 local a week on.'
            );
            Assert.areEqual(
                'Food pantry sort: 8 Mar 2026, 9:00 AM',
                shifts[1].Name,
                'Named in the org time zone.'
            );
            Assert.areEqual('Open', shifts[0].Status__c, 'Each shift is Open.');
            Assert.areEqual(4, shifts[0].Volunteers_Needed__c, 'The schedule places are copied.');
            Assert.areEqual(
                Date.newInstance(2026, 3, 16),
                createdThrough(schedule.Id),
                'Created Through is the horizon.'
            );
        }
    }

    @IsTest
    static void aRerunNeverCreatesADayTwiceAndADeletedShiftStaysDeleted() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            useClock(MONDAY_NOON);
            VolunteersTestData.shiftHorizonWeeks(2);
            Shift_Schedule__c schedule = saved(
                'Saturday;Sunday',
                Date.newInstance(2026, 2, 28),
                null
            );
            run(schedule.Id);

            Test.startTest();
            Integer again = run(schedule.Id);
            Volunteer_Shift__c sunday = shiftsOf(schedule.Id)[1];
            delete sunday;
            Integer afterDelete = run(schedule.Id);
            update as system new Shift_Schedule__c(Id = schedule.Id, Created_Through__c = null);
            Integer afterReset = run(schedule.Id);
            Test.stopTest();

            Assert.areEqual(0, again, 'A second run creates nothing.');
            Assert.areEqual(
                0,
                afterDelete,
                'A deleted shift is not created again by the next run.'
            );
            Assert.areEqual(
                1,
                afterReset,
                'With Created Through cleared, only the missing day is created.'
            );
            Assert.areEqual(4, shiftsOf(schedule.Id).size(), 'No day holds two shifts.');
        }
    }

    @IsTest
    static void aLongerHorizonExtendsAndAShorterOneRemovesNothing() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            useClock(MONDAY_NOON);
            Shift_Schedule__c schedule = saved(
                'Saturday;Sunday',
                Date.newInstance(2026, 2, 28),
                null
            );

            Test.startTest();
            VolunteersTestData.shiftHorizonWeeks(1);
            Integer oneWeek = run(schedule.Id);
            VolunteersTestData.shiftHorizonWeeks(3);
            Integer threeWeeks = run(schedule.Id);
            VolunteersTestData.shiftHorizonWeeks(1);
            Integer backToOne = run(schedule.Id);
            Test.stopTest();

            Assert.areEqual(2, oneWeek, 'One week ahead: 7 and 8 March.');
            Assert.areEqual(4, threeWeeks, 'Three weeks ahead adds 14, 15, 21 and 22 March.');
            Assert.areEqual(0, backToOne, 'A shorter horizon creates nothing.');
            Assert.areEqual(6, shiftsOf(schedule.Id).size(), 'And removes nothing.');
            Assert.areEqual(
                Date.newInstance(2026, 3, 23),
                createdThrough(schedule.Id),
                'Created Through never moves back.'
            );
        }
    }

    @IsTest
    static void theEndDateIsTheLastShiftDay() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            useClock(MONDAY_NOON);
            VolunteersTestData.shiftHorizonWeeks(4);
            Shift_Schedule__c schedule = saved(
                'Saturday;Sunday',
                Date.newInstance(2026, 2, 28),
                Date.newInstance(2026, 3, 14)
            );

            Test.startTest();
            Integer created = run(schedule.Id);
            Test.stopTest();

            Assert.areEqual(3, created, '7, 8 and 14 March, and nothing after the end date.');
            Assert.areEqual(
                Date.newInstance(2026, 3, 14),
                createdThrough(schedule.Id),
                'Created Through stops at the end date.'
            );
        }
    }

    @IsTest
    static void aShiftTodayThatHasStartedIsNotCreated() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            // Saturday 7 March 2026, 10:00 in New York.
            useClock(Datetime.newInstanceGmt(2026, 3, 7, 15, 0, 0));
            VolunteersTestData.shiftHorizonWeeks(1);
            Shift_Schedule__c schedule = saved('Saturday', Date.newInstance(2026, 3, 7), null);

            Test.startTest();
            Integer created = run(schedule.Id);
            Test.stopTest();

            Assert.areEqual(1, created, 'Only 14 March: the 9:00 shift today has already started.');
        }
    }

    @IsTest
    static void nothingRunsForAnInactiveScheduleOrWhileTheModuleIsOff() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            useClock(MONDAY_NOON);
            VolunteersTestData.shiftHorizonWeeks(2);
            Shift_Schedule__c schedule = saved('Saturday', Date.newInstance(2026, 2, 28), null);
            AutomationControl.bypass(RULES);
            update new Shift_Schedule__c(Id = schedule.Id, Active__c = false);
            AutomationControl.clearBypass(RULES);

            Test.startTest();
            Integer inactive = run(schedule.Id);
            AutomationControl.bypass(RULES);
            update new Shift_Schedule__c(Id = schedule.Id, Active__c = true);
            AutomationControl.clearBypass(RULES);
            BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
            settings.Modules_Turned_Off__c = ShiftScheduleService.MODULE_NAME;
            TestDataFactory.saveSettings(settings);
            Integer turnedOff = run(schedule.Id);
            Test.stopTest();

            Assert.areEqual(0, inactive, 'An inactive schedule creates no shift.');
            Assert.areEqual(0, turnedOff, 'Nothing runs while Volunteers is turned off.');
            Assert.isTrue(ShiftScheduleService.isTurnedOff(), 'The module reads as off.');
        }
    }
}
