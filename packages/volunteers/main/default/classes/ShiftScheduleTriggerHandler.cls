/**
 * Record-level rules for Shift_Schedule__c, run by the Core trigger dispatcher through the
 * registry row `Shift_Schedule_Rules`, switchable from the console (ADR-0017, ADR-0128).
 *
 * - R-SSC3: saving a schedule queues a run for it (`ShiftScheduleGenerator`), so its shifts
 *   appear without waiting for the night.
 * - R-SSC4: a change to the pattern removes the future shifts with no sign-ups or hours that are
 *   not Cancelled, clears Created Through and queues a run that recreates them from the new
 *   pattern.
 * - R-SSC5: clearing Active removes the same shifts and clears Created Through; an earlier End
 *   Date removes those after it and moves Created Through back to it; deleting the schedule removes every one of them, and the shifts
 *   kept lose their link through the lookup's SetNull.
 *
 * Shifts Kept records how many future shifts with a sign-up or hours such a save kept (Cancelled
 * shifts are kept but not counted), which is how the save tells the coordinator. A later save that
 * changes neither the pattern nor the end clears it. The removal runs before the save, so a save
 * that fails removes nothing.
 *
 * R-SSC6: a save removes shifts inline only while the transaction has DML rows to spare. An update
 * marks the rest of its schedules Rebuild Pending, and the run it queues, or failing that the
 * nightly run, removes their shifts before creating any. A delete takes the Ids of the rest's
 * removable shifts before the platform empties their link, and `ShiftScheduleRemovalJob` removes
 * them.
 */
@NamespaceAccessible
public with sharing class ShiftScheduleTriggerHandler extends TriggerHandler {
    /** The fields whose change is a new pattern (R-SSC4). End Date alone is an ending (R-SSC5). */
    private static final List<Schema.SObjectField> PATTERN_FIELDS = new List<Schema.SObjectField>{
        Shift_Schedule__c.Weekdays__c,
        Shift_Schedule__c.Every_N_Weeks__c,
        Shift_Schedule__c.Start_Time__c,
        Shift_Schedule__c.End_Time__c,
        Shift_Schedule__c.Start_Date__c,
        Shift_Schedule__c.Volunteers_Needed__c,
        Shift_Schedule__c.Location__c
    };

    @NamespaceAccessible
    public ShiftScheduleTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'ShiftScheduleTriggerHandler';
    }

    public override void afterInsert() {
        Set<Id> toRun = new Set<Id>();
        for (Shift_Schedule__c schedule : (List<Shift_Schedule__c>) Trigger.new) {
            if (schedule.Active__c == true) {
                toRun.add(schedule.Id);
            }
        }
        ShiftScheduleGenerator.queue(toRun);
    }

    public override void beforeUpdate() {
        Map<Id, Shift_Schedule__c> oldById = (Map<Id, Shift_Schedule__c>) Trigger.oldMap;
        Map<Id, Date> keepThrough = new Map<Id, Date>();
        Set<Id> restart = new Set<Id>();
        for (Shift_Schedule__c schedule : (List<Shift_Schedule__c>) Trigger.new) {
            Shift_Schedule__c old = oldById.get(schedule.Id);
            Boolean ended = old.Active__c == true && schedule.Active__c != true;
            if (ended || patternChanged(schedule, old)) {
                keepThrough.put(schedule.Id, null);
                restart.add(schedule.Id);
            } else if (endsEarlier(schedule, old)) {
                keepThrough.put(schedule.Id, schedule.End_Date__c);
            }
        }
        Map<Id, Date> inline = new Map<Id, Date>();
        Set<Id> deferred = new Set<Id>();
        Integer budget = ShiftScheduleService.inlineScheduleBudget();
        for (Id scheduleId : keepThrough.keySet()) {
            if (inline.size() < budget) {
                inline.put(scheduleId, keepThrough.get(scheduleId));
            } else {
                deferred.add(scheduleId);
            }
        }
        Map<Id, Integer> kept = ShiftScheduleService.removeFutureShifts(inline);
        for (Shift_Schedule__c schedule : (List<Shift_Schedule__c>) Trigger.new) {
            Shift_Schedule__c old = oldById.get(schedule.Id);
            if (kept.containsKey(schedule.Id)) {
                schedule.Shifts_Kept__c = kept.get(schedule.Id);
            } else if (deferred.contains(schedule.Id)) {
                // The run removes the shifts after Created Through, as set below, and records
                // the count.
                schedule.Rebuild_Pending__c = true;
                schedule.Shifts_Kept__c = null;
            } else if (
                schedule.Shifts_Kept__c == old.Shifts_Kept__c &&
                schedule.Created_Through__c == old.Created_Through__c &&
                schedule.Rebuild_Pending__c == old.Rebuild_Pending__c
            ) {
                // A save that changes neither the pattern nor the end: the last count is stale.
                // A run moving Created Through or finishing a rebuild keeps it.
                schedule.Shifts_Kept__c = null;
            }
            if (restart.contains(schedule.Id)) {
                schedule.Created_Through__c = null;
            } else if (
                keepThrough.get(schedule.Id) != null &&
                schedule.Created_Through__c > schedule.End_Date__c
            ) {
                // The days after the new end are gone, so a later End Date creates them again.
                schedule.Created_Through__c = schedule.End_Date__c;
            }
        }
    }

    /**
     * Queues a run for a schedule marked Rebuild Pending, active or not, and for an active
     * schedule whose pattern changed, that was turned back on, or whose End Date moved. The run's
     * own bookkeeping save clears the mark and queues nothing.
     */
    public override void afterUpdate() {
        Map<Id, Shift_Schedule__c> oldById = (Map<Id, Shift_Schedule__c>) Trigger.oldMap;
        Set<Id> toRun = new Set<Id>();
        for (Shift_Schedule__c schedule : (List<Shift_Schedule__c>) Trigger.new) {
            Shift_Schedule__c old = oldById.get(schedule.Id);
            if (schedule.Rebuild_Pending__c == true) {
                toRun.add(schedule.Id);
                continue;
            }
            if (schedule.Active__c != true) {
                continue;
            }
            if (
                old.Active__c != true ||
                patternChanged(schedule, old) ||
                schedule.End_Date__c != old.End_Date__c
            ) {
                toRun.add(schedule.Id);
            }
        }
        ShiftScheduleGenerator.queue(toRun);
    }

    /**
     * R-SSC5 and R-SSC6: removes every future removable shift of the deleted schedules, inline
     * within the budget and through `ShiftScheduleRemovalJob` for the rest.
     */
    public override void beforeDelete() {
        Map<Id, Date> inline = new Map<Id, Date>();
        Set<Id> deferred = new Set<Id>();
        Integer budget = ShiftScheduleService.inlineScheduleBudget();
        for (Id scheduleId : Trigger.oldMap.keySet()) {
            if (inline.size() < budget) {
                inline.put(scheduleId, null);
            } else {
                deferred.add(scheduleId);
            }
        }
        ShiftScheduleService.removeFutureShifts(inline);
        if (!deferred.isEmpty()) {
            ShiftScheduleRemovalJob.queue(ShiftScheduleService.removableFutureShiftIds(deferred));
        }
    }

    private static Boolean patternChanged(Shift_Schedule__c schedule, Shift_Schedule__c old) {
        for (Schema.SObjectField field : PATTERN_FIELDS) {
            if (schedule.get(field) != old.get(field)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean endsEarlier(Shift_Schedule__c schedule, Shift_Schedule__c old) {
        return schedule.End_Date__c != null &&
            (old.End_Date__c == null ||
            schedule.End_Date__c < old.End_Date__c);
    }
}
