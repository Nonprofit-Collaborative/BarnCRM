/**
 * The Volunteers module's Health Check findings (canonical model Part G, "Health Check"; ADR-0057's
 * extension seam). Core finds this class by name (`HealthCheckExtensions.EXTENSION_CLASSES`) and
 * folds the findings into its one report, under the key `volunteers_extension`.
 *
 * Three questions about the records: hours waiting too long for approval, past shifts nobody
 * closed, and recurring schedules that have not created shifts as far ahead as Volunteer Settings
 * asks. Each reads organization-wide state, so they are asked only of a viewer who may manage
 * settings, as Giving's and Rollup Builder's are, and not at all while the module is turned off
 * (its automations and schedules stop then, on purpose). Each check is isolated: one that throws
 * becomes a single "check failed" finding and the rest still stand.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class VolunteersHealthCheckExtension implements HealthCheckExtension {
    /** Hours entered longer ago than this, still Submitted, are waiting too long. */
    @TestVisible
    private static Integer hoursWaitingDays = 14;

    /** A shift that ended longer ago than this and is still Open was never closed. */
    @TestVisible
    private static final Integer PAST_SHIFT_DAYS = 7;

    /** How far short of the horizon a schedule may be before it is reported (29T). */
    private static final Integer HORIZON_SLACK_DAYS = 2;

    /** Counts stop here, and the finding says "more than" this many. */
    @TestVisible
    private static Integer countCap = 1000;

    /** How many example records a finding links to. */
    private static final Integer LINKS_SHOWN = 5;

    @NamespaceAccessible
    public VolunteersHealthCheckExtension() {
        // Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
    }

    public List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
        if (!HealthCheckService.canManageSettings() || ShiftScheduleService.isTurnedOff()) {
            return found;
        }
        for (
            String check : new List<String>{
                'volunteer_hours_waiting',
                'volunteer_past_shifts_open',
                'volunteer_schedule_horizon'
            }
        ) {
            try {
                HealthCheckService.Finding finding = run(check);
                if (finding != null) {
                    found.add(finding);
                }
            } catch (Exception e) {
                found.add(HealthCheckService.checkFailed(check, e));
            }
        }
        return found;
    }

    private static HealthCheckService.Finding run(String check) {
        switch on check {
            when 'volunteer_hours_waiting' {
                return hoursWaiting();
            }
            when 'volunteer_past_shifts_open' {
                return pastShiftsOpen();
            }
            when else {
                return scheduleHorizon();
            }
        }
    }

    // ------------------------------------------------------------------------------ findings

    /**
     * Submitted hours entered more than 14 days ago (R-VG5). They count in no total and no letter
     * until a coordinator decides, so the volunteer's totals look low. A warning: somebody is
     * waiting.
     */
    private static HealthCheckService.Finding hoursWaiting() {
        List<Volunteer_Hours__c> waiting = VolunteerHealthCheckSelector.hoursWaitingSince(
            Datetime.now().addDays(-hoursWaitingDays),
            countCap + 1
        );
        if (waiting.isEmpty()) {
            return null;
        }
        return new HealthCheckService.Finding(
                'volunteer_hours_waiting',
                String.format(
                    Label.Volunteers_HealthCheck_HoursWaitingTitle,
                    new List<Object>{ counted(waiting.size()), hoursWaitingDays.format() }
                ),
                withFirstListed(Label.Volunteers_HealthCheck_HoursWaitingDetail, waiting.size()),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                Label.Volunteers_HealthCheck_HoursWaitingFix,
                '/lightning/n/' + NamespaceUtil.qualify('Volunteer_Approve_Hours')
            )
            .withLinks(links(waiting));
    }

    /**
     * Open shifts that ended more than seven days ago. Nothing closes a shift by itself, so this
     * usually means attendance was never marked and nobody's hours were written (R-VU3).
     * Information: the records are not wrong, they are unfinished.
     */
    private static HealthCheckService.Finding pastShiftsOpen() {
        List<Volunteer_Shift__c> open = VolunteerHealthCheckSelector.openShiftsEndedBefore(
            Datetime.now().addDays(-PAST_SHIFT_DAYS),
            countCap + 1
        );
        if (open.isEmpty()) {
            return null;
        }
        String detail = String.format(
            Label.Volunteers_HealthCheck_PastShiftsDetail,
            new List<Object>{ PAST_SHIFT_DAYS.format() }
        );
        return new HealthCheckService.Finding(
                'volunteer_past_shifts_open',
                String.format(
                    Label.Volunteers_HealthCheck_PastShiftsTitle,
                    new List<Object>{ counted(open.size()) }
                ),
                withFirstListed(detail, open.size()),
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                Label.Volunteers_HealthCheck_PastShiftsFix,
                '/lightning/o/' +
                    Volunteer_Shift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getName() +
                    '/list'
            )
            .withLinks(links(open));
    }

    /**
     * Active schedules whose Created Through is more than two days short of the horizon, or of
     * their End Date when that is sooner (29T). Volunteers cannot be booked for the days missing.
     */
    private static HealthCheckService.Finding scheduleHorizon() {
        Date today = ShiftScheduleService.today();
        Integer weeks = VolunteerSettings.shiftHorizonWeeks();
        Date horizon = today.addDays(7 * weeks);
        List<Shift_Schedule__c> behind = new List<Shift_Schedule__c>();
        for (
            Shift_Schedule__c schedule : VolunteerHealthCheckSelector.schedulesShortOf(
                today,
                horizon,
                horizon.addDays(-HORIZON_SLACK_DAYS),
                countCap + 1
            )
        ) {
            Date expected = schedule.End_Date__c != null &&
                schedule.End_Date__c < horizon
                ? schedule.End_Date__c
                : horizon;
            if (
                schedule.Created_Through__c == null ||
                schedule.Created_Through__c < expected.addDays(-HORIZON_SLACK_DAYS)
            ) {
                behind.add(schedule);
            }
        }
        if (behind.isEmpty()) {
            return null;
        }
        String detail = String.format(
            Label.Volunteers_HealthCheck_HorizonDetail,
            new List<Object>{ weeks.format() }
        );
        return new HealthCheckService.Finding(
                'volunteer_schedule_horizon',
                String.format(
                    Label.Volunteers_HealthCheck_HorizonTitle,
                    new List<Object>{ counted(behind.size()) }
                ),
                withFirstListed(detail, behind.size()),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withLinks(links(behind));
    }

    // ------------------------------------------------------------------------------- helpers

    private static String counted(Integer howMany) {
        return howMany > countCap
            ? String.format(
                  Label.Volunteers_HealthCheck_MoreThan,
                  new List<Object>{ countCap.format() }
              )
            : howMany.format();
    }

    private static String withFirstListed(String detail, Integer howMany) {
        return detail +
            ' ' +
            String.format(
                Label.Volunteers_HealthCheck_FirstListed,
                new List<Object>{ String.valueOf(Math.min(howMany, LINKS_SHOWN)) }
            );
    }

    private static List<HealthCheckService.Link> links(List<SObject> records) {
        List<HealthCheckService.Link> result = new List<HealthCheckService.Link>();
        for (Integer i = 0; i < records.size() && i < LINKS_SHOWN; i++) {
            result.add(new HealthCheckService.Link(records[i]));
        }
        return result;
    }
}
