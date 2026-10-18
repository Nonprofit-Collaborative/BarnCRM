/**
 * Recurring shifts (V-07, ADR-0128, canonical model Section 29T): which days a schedule falls on,
 * the run that creates its shifts up to the horizon, and the removal of the future shifts an edit
 * or an ending no longer wants.
 *
 * A run (R-SSC2) locks its schedules first (R-SSC3), creates the days after Created Through (or
 * from today, if later) up to the horizon and End Date, skips a day that already has a shift
 * from the schedule, and moves Created Through forward. Times are read in the org's default time
 * zone (R-SSC1), so a 9:00 shift starts at 9:00 local time on both sides of a daylight saving
 * change, whoever runs it.
 *
 * Shifts are created in user mode, as the person who saved the schedule or scheduled the nightly
 * run. Created Through, Shifts Kept and the removal of a schedule's own future shifts run in
 * system mode: they are the schedule's bookkeeping, read only in every permission set, and a
 * Coordinator or Staff user who may edit a schedule holds no delete on shifts.
 */
public with sharing class ShiftScheduleService {
    public static final String MODULE_NAME = 'Volunteers';
    public static final String STATUS_OPEN = 'Open';
    public static final String STATUS_CANCELLED = 'Cancelled';

    /**
     * DML rows a save leaves unused for everything else in its transaction (the save's own rows,
     * other triggers), before it removes shifts inline (R-SSC6).
     */
    private static final Integer ROW_RESERVE = 2000;

    private static final String NAME_FORMAT = 'd MMM yyyy, h:mm a';
    private static final Integer NAME_LENGTH = 80;
    /** Monday first. Not named WEEKDAYS: Apex names are case-insensitive. */
    private static final List<String> DAY_NAMES = new List<String>{
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
    };
    /** A Monday, from which the weekday of any later date is counted. */
    private static final Date A_MONDAY = Date.newInstance(1900, 1, 1);

    /** The clock and time zone, set by tests so a run does not depend on the real date. */
    @TestVisible
    private static Datetime nowOverride;
    @TestVisible
    private static String timeZoneOverride;

    private static String orgTimeZone;

    /** Whether the module is turned off in Module Manager, when nothing here runs. */
    public static Boolean isTurnedOff() {
        return ModuleManagerService.turnedOff().contains(MODULE_NAME.toLowerCase());
    }

    /**
     * Creates the shifts these schedules are missing up to the horizon (R-SSC2) and returns how
     * many it created. Inactive and ended schedules create nothing.
     */
    public static Integer run(Set<Id> scheduleIds) {
        if (scheduleIds == null || scheduleIds.isEmpty() || isTurnedOff()) {
            return 0;
        }
        List<Shift_Schedule__c> schedules = ShiftScheduleSelector.lockForRun(scheduleIds);
        Date runDay = today();
        Date horizon = runDay.addDays(7 * VolunteerSettings.shiftHorizonWeeks());
        Datetime runStart = now();

        Map<Id, Set<Date>> takenBySchedule = takenDays(
            new Map<Id, Shift_Schedule__c>(schedules).keySet(),
            toOrgDatetime(runDay, Time.newInstance(0, 0, 0, 0))
        );
        List<Volunteer_Shift__c> created = new List<Volunteer_Shift__c>();
        List<Shift_Schedule__c> moved = new List<Shift_Schedule__c>();
        for (Shift_Schedule__c schedule : schedules) {
            if (schedule.Active__c != true) {
                continue;
            }
            Date fromDay = latest(runDay, schedule.Start_Date__c);
            if (schedule.Created_Through__c != null) {
                fromDay = latest(fromDay, schedule.Created_Through__c.addDays(1));
            }
            Date untilDay = schedule.End_Date__c == null
                ? horizon
                : earliest(horizon, schedule.End_Date__c);
            if (fromDay == null || fromDay > untilDay) {
                continue;
            }
            Set<Date> taken = takenBySchedule.containsKey(schedule.Id)
                ? takenBySchedule.get(schedule.Id)
                : new Set<Date>();
            for (Date day : shiftDays(schedule, fromDay, untilDay)) {
                if (taken.contains(day)) {
                    continue;
                }
                Volunteer_Shift__c shift = newShift(schedule, day);
                if (shift.Start_Time__c < runStart) {
                    continue;
                }
                created.add(shift);
            }
            moved.add(new Shift_Schedule__c(Id = schedule.Id, Created_Through__c = untilDay));
        }
        if (!created.isEmpty()) {
            insert as user created;
        }
        if (!moved.isEmpty()) {
            // System mode: Created Through is read only in every permission set (29T).
            update as system moved;
        }
        return created.size();
    }

    /**
     * The days from `fromDay` to `untilDay`, both included, that are shift days of this schedule
     * (R-SSC1): the weekday is chosen, the day is within Start Date and End Date, and the whole
     * weeks between the Monday of Start Date's week and the Monday of its own divide by Every N
     * Weeks.
     */
    public static List<Date> shiftDays(Shift_Schedule__c schedule, Date fromDay, Date untilDay) {
        List<Date> days = new List<Date>();
        Set<Integer> chosen = chosenWeekdays(schedule.Weekdays__c);
        if (chosen.isEmpty() || schedule.Start_Date__c == null || fromDay == null) {
            return days;
        }
        Integer everyN = schedule.Every_N_Weeks__c == null ||
            schedule.Every_N_Weeks__c < 1
            ? 1
            : schedule.Every_N_Weeks__c.intValue();
        Date firstMonday = mondayOf(schedule.Start_Date__c);
        Date day = latest(fromDay, schedule.Start_Date__c);
        Date lastDay = schedule.End_Date__c == null
            ? untilDay
            : earliest(untilDay, schedule.End_Date__c);
        while (day <= lastDay) {
            Integer weeks = firstMonday.daysBetween(mondayOf(day)) / 7;
            if (chosen.contains(weekdayIndex(day)) && Math.mod(weeks, everyN) == 0) {
                days.add(day);
            }
            day = day.addDays(1);
        }
        return days;
    }

    /**
     * Removes the schedules' future shifts that have no sign-up or hours record and are not
     * Cancelled (R-SSC4, R-SSC5). A schedule mapped to a date keeps the shifts on or before that day (an
     * earlier End Date); one mapped to null loses every future shift. Returns, per schedule, how
     * many shifts it would have removed but kept because they have a sign-up or hours; a
     * Cancelled shift is kept too but is not counted.
     */
    public static Map<Id, Integer> removeFutureShifts(Map<Id, Date> keepThrough) {
        Map<Id, Integer> kept = new Map<Id, Integer>();
        if (keepThrough == null || keepThrough.isEmpty()) {
            return kept;
        }
        for (Id scheduleId : keepThrough.keySet()) {
            kept.put(scheduleId, 0);
        }
        Datetime cutoff = now();
        List<Volunteer_Shift__c> future = new List<Volunteer_Shift__c>();
        for (
            Volunteer_Shift__c shift : ShiftScheduleSelector.shiftsFrom(
                keepThrough.keySet(),
                cutoff
            )
        ) {
            Date lastKept = keepThrough.get(shift.Shift_Schedule__c);
            Boolean uncovered = lastKept == null || orgDate(shift.Start_Time__c) > lastKept;
            if (shift.Start_Time__c > cutoff && uncovered) {
                future.add(shift);
            }
        }
        Set<Id> booked = ShiftScheduleSelector.shiftsInUse(
            new Map<Id, Volunteer_Shift__c>(future).keySet()
        );
        List<Volunteer_Shift__c> removed = new List<Volunteer_Shift__c>();
        for (Volunteer_Shift__c shift : future) {
            if (shift.Status__c == STATUS_CANCELLED) {
                continue;
            }
            if (booked.contains(shift.Id)) {
                kept.put(shift.Shift_Schedule__c, kept.get(shift.Shift_Schedule__c) + 1);
            } else {
                removed.add(shift);
            }
        }
        if (!removed.isEmpty()) {
            // System mode: the schedule's own unbooked shifts, which a Coordinator or Staff user
            // who may edit the schedule cannot delete with their own access (29T).
            delete as system removed;
        }
        return kept;
    }

    /**
     * How many schedules a save may remove the future shifts of inline (R-SSC6): the DML rows
     * still free in this transaction, less a reserve, over the most shifts one schedule can hold
     * (every day to the horizon). The rest are rebuilt by `ShiftScheduleBatch`.
     */
    public static Integer inlineScheduleBudget() {
        Integer free = Limits.getLimitDmlRows() - Limits.getDmlRows() - ROW_RESERVE;
        return Math.max(0, free / (7 * VolunteerSettings.shiftHorizonWeeks()));
    }

    /**
     * The deferred half of R-SSC4 and R-SSC5, run a chunk of schedules per transaction: removes
     * their future shifts as the save would have, records Shifts Kept, clears Created Through
     * where the save would have, and creates the shifts the pattern now calls for.
     */
    public static void rebuild(Map<Id, Date> keepThrough) {
        if (keepThrough == null || keepThrough.isEmpty() || isTurnedOff()) {
            return;
        }
        Map<Id, Integer> kept = removeFutureShifts(keepThrough);
        List<Shift_Schedule__c> marks = new List<Shift_Schedule__c>();
        for (Id scheduleId : keepThrough.keySet()) {
            Shift_Schedule__c mark = new Shift_Schedule__c(
                Id = scheduleId,
                Shifts_Kept__c = kept.get(scheduleId)
            );
            if (keepThrough.get(scheduleId) == null) {
                mark.Created_Through__c = null;
            }
            marks.add(mark);
        }
        // System mode: Shifts Kept and Created Through are read only in every permission set (29T).
        update as system marks;
        run(keepThrough.keySet());
    }

    /** A Datetime for this local day and time in the org's time zone, across daylight saving. */
    public static Datetime toOrgDatetime(Date day, Time localTime) {
        TimeZone zone = TimeZone.getTimeZone(timeZone());
        Datetime wallClock = Datetime.newInstanceGmt(day, localTime);
        Integer firstOffset = zone.getOffset(wallClock);
        Datetime guess = wallClock.addSeconds(-firstOffset / 1000);
        Integer secondOffset = zone.getOffset(guess);
        if (secondOffset != firstOffset) {
            Datetime corrected = wallClock.addSeconds(-secondOffset / 1000);
            // A time the clocks skip (2:30 on the spring change) keeps the first reading.
            if (zone.getOffset(corrected) == secondOffset) {
                guess = corrected;
            }
        }
        return guess;
    }

    /** The day this moment falls on in the org's time zone. */
    public static Date orgDate(Datetime moment) {
        return Date.valueOf(moment.format('yyyy-MM-dd', timeZone()));
    }

    public static Datetime now() {
        return nowOverride == null ? Datetime.now() : nowOverride;
    }

    /** Today in the org's time zone. */
    public static Date today() {
        return orgDate(now());
    }

    private static String timeZone() {
        if (timeZoneOverride != null) {
            return timeZoneOverride;
        }
        if (orgTimeZone == null) {
            orgTimeZone = ShiftScheduleSelector.orgTimeZone();
        }
        return orgTimeZone;
    }

    private static Volunteer_Shift__c newShift(Shift_Schedule__c schedule, Date day) {
        Datetime startTime = toOrgDatetime(day, schedule.Start_Time__c);
        String name = schedule.Job__r?.Name == null
            ? null
            : (schedule.Job__r.Name +
                  ': ' +
                  startTime.format(NAME_FORMAT, timeZone()))
                  .abbreviate(NAME_LENGTH);
        return new Volunteer_Shift__c(
            Name = name,
            Volunteer_Job__c = schedule.Job__c,
            Shift_Schedule__c = schedule.Id,
            Start_Time__c = startTime,
            End_Time__c = toOrgDatetime(day, schedule.End_Time__c),
            Volunteers_Needed__c = schedule.Volunteers_Needed__c,
            Location__c = schedule.Location__c,
            Status__c = STATUS_OPEN
        );
    }

    /** Per schedule, the local days from `fromTime` on that already hold one of its shifts. */
    private static Map<Id, Set<Date>> takenDays(Set<Id> scheduleIds, Datetime fromTime) {
        Map<Id, Set<Date>> taken = new Map<Id, Set<Date>>();
        if (scheduleIds.isEmpty()) {
            return taken;
        }
        for (Volunteer_Shift__c shift : ShiftScheduleSelector.shiftsFrom(scheduleIds, fromTime)) {
            if (!taken.containsKey(shift.Shift_Schedule__c)) {
                taken.put(shift.Shift_Schedule__c, new Set<Date>());
            }
            taken.get(shift.Shift_Schedule__c).add(orgDate(shift.Start_Time__c));
        }
        return taken;
    }

    private static Set<Integer> chosenWeekdays(String weekdays) {
        Set<Integer> chosen = new Set<Integer>();
        if (String.isBlank(weekdays)) {
            return chosen;
        }
        for (String part : weekdays.split(';')) {
            Integer index = DAY_NAMES.indexOf(part.trim());
            if (index >= 0) {
                chosen.add(index);
            }
        }
        return chosen;
    }

    /** 0 for Monday to 6 for Sunday, whatever the user's locale calls the first day. */
    private static Integer weekdayIndex(Date day) {
        return Math.mod(A_MONDAY.daysBetween(day), 7);
    }

    private static Date mondayOf(Date day) {
        return day.addDays(-weekdayIndex(day));
    }

    private static Date latest(Date first, Date second) {
        if (first == null) {
            return second;
        }
        return second == null || first > second ? first : second;
    }

    private static Date earliest(Date first, Date second) {
        if (first == null) {
            return second;
        }
        return second == null || first < second ? first : second;
    }
}
