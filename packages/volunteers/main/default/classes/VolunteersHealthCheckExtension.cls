/**
 * The Volunteers module's Health Check findings and its one fix (canonical model Part G, "Health
 * Check"; ADR-0057's extension seam). Core finds this class by name
 * (`HealthCheckExtensions.EXTENSION_CLASSES`) and folds the findings into its one report, under
 * the key `volunteers_extension`.
 *
 * Five questions: hours waiting too long for approval, past shifts nobody closed, recurring
 * schedules that have not created shifts as far ahead as Volunteer Settings asks, coordinators
 * missing their permission set, and shipped volunteer totals turned off. Each reads
 * organization-wide state, and the fix gives a permission set, so they are asked only of a viewer
 * who may manage settings, as Giving's and Rollup Builder's are, and not at all while the module
 * is turned off (its automations, schedules and access sync all stop then, on purpose). Each check
 * is isolated: one that throws becomes a single "check failed" finding and the rest still stand.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class VolunteersHealthCheckExtension implements HealthCheckExtension, HealthCheckFixExtension {
    /** The fix that gives the coordinator set to coordinators who lack it (VolunteersAccessSync). */
    @NamespaceAccessible
    public static final String FIX_KEY_COORDINATOR_ACCESS = 'giveVolunteersCoordinatorAccess';

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

    private static final String COORDINATOR_GROUP = 'Volunteer_Coordinator';
    private static final String COORDINATOR_SET = 'Volunteers_Coordinator';

    /** A coordinator holding either set can approve hours and work with shifts. */
    private static final Set<String> COORDINATOR_SETS = new Set<String>{
        COORDINATOR_SET,
        VolunteersAccessSync.ADMIN_SET
    };

    /** The shift list view the past shifts finding opens. */
    @TestVisible
    private static final String PAST_SHIFTS_LIST_VIEW = 'Past_Shifts_Still_Open';

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
                'volunteer_schedule_horizon',
                'volunteer_coordinator_access',
                'volunteer_rollups_off'
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
            when 'volunteer_schedule_horizon' {
                return scheduleHorizon();
            }
            when 'volunteer_coordinator_access' {
                return coordinatorAccess();
            }
            when else {
                return rollupsOff();
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
        Integer howMany = waiting.size();
        return new HealthCheckService.Finding(
                'volunteer_hours_waiting',
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_HoursWaitingTitleOne,
                        Label.Volunteers_HealthCheck_HoursWaitingTitle
                    ),
                    new List<Object>{ counted(howMany), hoursWaitingDays.format() }
                ),
                withFirstListed(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_HoursWaitingDetailOne,
                        Label.Volunteers_HealthCheck_HoursWaitingDetail
                    ),
                    howMany
                ),
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
        Integer howMany = open.size();
        String detail = String.format(
            oneOrMany(
                howMany,
                Label.Volunteers_HealthCheck_PastShiftsDetailOne,
                Label.Volunteers_HealthCheck_PastShiftsDetail
            ),
            new List<Object>{ PAST_SHIFT_DAYS.format() }
        );
        return new HealthCheckService.Finding(
                'volunteer_past_shifts_open',
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_PastShiftsTitleOne,
                        Label.Volunteers_HealthCheck_PastShiftsTitle
                    ),
                    new List<Object>{ counted(howMany) }
                ),
                withFirstListed(detail, howMany),
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(Label.Volunteers_HealthCheck_PastShiftsFix, pastShiftsListUrl())
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
        Integer howMany = behind.size();
        String detail = String.format(
            oneOrMany(
                howMany,
                Label.Volunteers_HealthCheck_HorizonDetailOne,
                Label.Volunteers_HealthCheck_HorizonDetail
            ),
            new List<Object>{ weeks.format() }
        );
        return new HealthCheckService.Finding(
                'volunteer_schedule_horizon',
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_HorizonTitleOne,
                        Label.Volunteers_HealthCheck_HorizonTitle
                    ),
                    new List<Object>{ counted(howMany) }
                ),
                withFirstListed(detail, howMany),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withLinks(links(behind));
    }

    /**
     * People holding the Coordinator role with neither the Volunteers Coordinator set nor
     * Volunteers Admin (ADR-0127, decision 3; ADR-0131). The access sync gives the coordinator
     * set nightly; until it does they cannot approve hours. The fix asks the sync to run now.
     */
    private static HealthCheckService.Finding coordinatorAccess() {
        List<String> names = coordinatorsMissingTheirSet();
        if (names.isEmpty()) {
            return null;
        }
        Integer howMany = names.size();
        List<Object> values = new List<Object>{ String.valueOf(howMany), String.join(names, ', ') };
        return new HealthCheckService.Finding(
                'volunteer_coordinator_access',
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_CoordinatorAccessTitleOne,
                        Label.Volunteers_HealthCheck_CoordinatorAccessTitle
                    ),
                    values
                ),
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_CoordinatorAccessDetailOne,
                        Label.Volunteers_HealthCheck_CoordinatorAccessDetail
                    ),
                    values
                ),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withScope(names)
            .withFix(
                Label.Volunteers_HealthCheck_CoordinatorAccessFix,
                HealthCheckService.FIX_ACTION_PREFIX + FIX_KEY_COORDINATOR_ACCESS
            );
    }

    /**
     * Shipped volunteer totals (29O) whose definition is inactive. Information: an administrator
     * may turn one off on purpose. A shipped total that is missing altogether is Rollup Builder's
     * own finding, with its restore fix, so it is not reported twice here.
     */
    private static HealthCheckService.Finding rollupsOff() {
        Set<String> keys = VolunteerHealthCheckSelector.shippedRollupKeys(
            ShiftScheduleService.MODULE_NAME
        );
        if (keys.isEmpty()) {
            return null;
        }
        List<Rollup_Definition__c> off = VolunteerHealthCheckSelector.inactiveRollups(keys);
        if (off.isEmpty()) {
            return null;
        }
        List<String> names = new List<String>();
        for (Rollup_Definition__c definition : off) {
            names.add(definition.Name);
        }
        Integer howMany = off.size();
        List<Object> values = new List<Object>{ String.valueOf(howMany), String.join(names, ', ') };
        return new HealthCheckService.Finding(
                'volunteer_rollups_off',
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_RollupsOffTitleOne,
                        Label.Volunteers_HealthCheck_RollupsOffTitle
                    ),
                    values
                ),
                String.format(
                    oneOrMany(
                        howMany,
                        Label.Volunteers_HealthCheck_RollupsOffDetailOne,
                        Label.Volunteers_HealthCheck_RollupsOffDetail
                    ),
                    values
                ),
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                Label.Volunteers_HealthCheck_RollupsOffFix,
                '/lightning/n/' + NamespaceUtil.qualify('Rollup_Builder')
            );
    }

    // ----------------------------------------------------------------------------------- fix

    public List<String> fixScope(String fixKey) {
        return FIX_KEY_COORDINATOR_ACCESS.equals(fixKey) ? coordinatorsMissingTheirSet() : null;
    }

    public String fixLabel(String fixKey) {
        return FIX_KEY_COORDINATOR_ACCESS.equals(fixKey)
            ? Label.Volunteers_HealthCheck_CoordinatorAccessFix
            : null;
    }

    /**
     * Queues the module's access sync, which gives every Volunteers set to the people whose role
     * calls for it. Queued, because a permission set assignment is a setup object write and the
     * fix also logs the change to a record (mixed DML).
     */
    public String runFix(String fixKey, List<String> scope) {
        if (!FIX_KEY_COORDINATOR_ACCESS.equals(fixKey)) {
            return null;
        }
        new VolunteersAccessSync().requestSync();
        return String.format(
            Label.Volunteers_HealthCheck_CoordinatorAccessDone,
            new List<Object>{ String.join(scope, ', ') }
        );
    }

    // ------------------------------------------------------------------------------- helpers

    /**
     * The names, sorted, of active coordinators holding neither the coordinator set nor
     * Volunteers Admin, which grants all that the coordinator set does.
     */
    private static List<String> coordinatorsMissingTheirSet() {
        String prefix = NamespaceUtil.prefix();
        String namespace = String.isBlank(prefix) ? null : prefix.removeEnd('__');
        VolunteerHealthCheckSelector.GroupHolders coordinators = VolunteerHealthCheckSelector.groupHoldersWithSet(
            COORDINATOR_GROUP,
            COORDINATOR_SETS,
            namespace
        );
        Set<Id> missing = new Set<Id>(coordinators.names.keySet());
        missing.removeAll(coordinators.holdingSetDirectly);
        if (!missing.isEmpty()) {
            // Only those without a direct assignment may still hold one through another group.
            missing.removeAll(
                VolunteerHealthCheckSelector.setHoldersAmong(missing, COORDINATOR_SETS, namespace)
            );
        }
        List<String> names = new List<String>();
        for (Id userId : missing) {
            names.add(coordinators.names.get(userId));
        }
        names.sort();
        return names;
    }

    private static String counted(Integer howMany) {
        return howMany > countCap
            ? String.format(
                  Label.Volunteers_HealthCheck_MoreThan,
                  new List<Object>{ countCap.format() }
              )
            : howMany.format();
    }

    private static String withFirstListed(String detail, Integer howMany) {
        if (howMany == 1) {
            return detail + ' ' + Label.Volunteers_HealthCheck_FirstListedOne;
        }
        return detail +
            ' ' +
            String.format(
                Label.Volunteers_HealthCheck_FirstListed,
                new List<Object>{ String.valueOf(Math.min(howMany, LINKS_SHOWN)) }
            );
    }

    /** The one-item label for a count of exactly one, otherwise the many-item label. */
    private static String oneOrMany(Integer howMany, String one, String many) {
        return howMany == 1 ? one : many;
    }

    /** The shift list view of Open shifts dated before today. */
    private static String pastShiftsListUrl() {
        return '/lightning/o/' +
            Volunteer_Shift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            '/list?filterName=' +
            NamespaceUtil.qualify(PAST_SHIFTS_LIST_VIEW);
    }

    private static List<HealthCheckService.Link> links(List<SObject> records) {
        List<HealthCheckService.Link> result = new List<HealthCheckService.Link>();
        for (Integer i = 0; i < records.size() && i < LINKS_SHOWN; i++) {
            result.add(new HealthCheckService.Link(records[i]));
        }
        return result;
    }
}
